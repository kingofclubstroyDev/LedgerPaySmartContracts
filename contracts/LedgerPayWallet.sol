// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./BaseWallet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./IWorldID.sol";
import "./ByteHasher.sol";

import {
    ISuperfluid
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol"; //"@superfluid-finance/ethereum-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { 
    IConstantFlowAgreementV1 
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {
    CFAv1Library
} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";

import {
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract LedgerPayWallet is BaseWallet, Initializable {
    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;
    using ByteHasher for bytes;

    string public constant WORLDID_ACTION_ID = "wid_821ed43cf6a99e2d32bbfe27fe346844";

    /// @notice explicit sizes of nonce, to fit a single storage cell with "owner"
    uint96 private _nonce;
    address public owner;

    /// @notice the threshold of guardians required to successfully recover a wallet
    uint256 public threshold;

    /// @notice the current number of guardians
    uint256 public numberGuardians;

    /// @notice indicates if the wallet is in a recovery state
    bool public inRecovery;

    /// @notice the round of recovery the wallet is in, helps to separate recovery proposals
    uint256 public recoveryRound;

    /// @notice mapping of guardians, based on a hash of their address to help hide identity
    mapping(bytes32 => bool) public Guardians;

    /// @notice Mapping of a guardian to their most recent proposed recovery data
    mapping(address => RecoveryData) public guardiansRecovery;

    /// @notice data guardians propose to make a recovery
    struct RecoveryData {
        address proposedOwner;
        uint256 recoveryRound;
    }

    EntryPoint private _entryPoint;

    /// WorldId Values

    /// @dev The WorldID instance that will be used for verifying proofs
    IWorldID internal worldId;

    /// @dev The WorldID group ID (1)
    uint256 internal constant groupId = 1;

    /// @dev Set by the owner using WorldId to allow them to recover their wallet if they lose the keys
    uint private recoveryHash;
    bool public allowWorldIdRecovery;

    ///@dev superfluid

     using CFAv1Library for CFAv1Library.InitData;
    
    //initialize cfaV1 variable
    CFAv1Library.InitData public cfaV1;


    function initialize(EntryPoint newEntryPoint, address _owner, IWorldID _worldId) external initializer {

        _entryPoint = newEntryPoint;
        owner = _owner;
        worldId = _worldId;
        
        this.initSuperfluid(ISuperfluid(0x3E14dC1b13c488a8d5D310918780c983bD5982E7));
    }

    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == address(this), "Only owner can call");
        _;
    }

    modifier onlyGuardian() {
        require(Guardians[keccak256(abi.encodePacked(msg.sender, address(this)))], "Only a guardian can call");
        _;
    }

    modifier notInRecovery {
        require(!inRecovery, "Wallet is in recovery mode");
        _;
    }

    modifier onlyInRecovery {
        require(inRecovery, "Wallet is not in recovery mode");
        _;
    }

    /**
     * return the entryPoint used by this wallet.
     * subclass should return the current entryPoint used by this wallet.
     */
    function entryPoint() public view override returns (EntryPoint) {
        return _entryPoint;
    }

    /**
     * return the wallet nonce.
     * subclass should return a nonce value that is used both by _validateAndUpdateNonce, and by the external provider (to read the current nonce)
     */
    function nonce() public view override returns (uint256) {
        return _nonce;
    }

    /**
     * transfer eth value to a destination address
    */
    function transfer(address payable dest, uint256 amount) external onlyOwner {
        dest.transfer(amount);
    }

    /**
     * execute a transaction (called directly from owner, not by entryPoint)
     */
    function exec(address dest, uint256 value, bytes calldata func) external onlyOwner {
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transaction
     */
    function execBatch(address[] calldata dest, bytes[] calldata func) external onlyOwner {
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /**
     * change entry-point:
     * a wallet must have a method for replacing the entryPoint, in case the the entryPoint is
     * upgraded to a newer version.
     */
    function _updateEntryPoint(address newEntryPoint) internal override {
        emit EntryPointChanged(address(_entryPoint), newEntryPoint);
        _entryPoint = EntryPoint(payable(newEntryPoint));
    }

    /**
     * validate the userOp is correct.
     * revert if it doesn't.
     * - must only be called from the entryPoint.
     * - make sure the signature is of our supported signer.
     * - validate current nonce matches request nonce, and increment it.
     * - pay prefund, in case current deposit is not enough
     */
    function _requireFromEntryPoint() internal override view {
        require(msg.sender == address(_entryPoint), "wallet: not from EntryPoint");
    }

    // called by entryPoint, only after validateUserOp succeeded.
    function execFromEntryPoint(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPoint();
        _call(dest, value, func);
    }

    /// implement template method of BaseWallet
    function _validateAndUpdateNonce(UserOperation calldata userOp) internal override {
        require(_nonce++ == userOp.nonce, "wallet: invalid nonce");
    }

    /// implement template method of BaseWallet
    function _validateSignature(UserOperation calldata userOp, bytes32 requestId) internal view override {
        bytes32 hash = requestId.toEthSignedMessageHash();
        require(owner == hash.recover(userOp.signature), "wallet: wrong signature");
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result,32), mload(result))
            }
        }
    }

    /**
     * check current wallet deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return _entryPoint.balanceOf(address(this));
    }

    /**
     * deposit more funds for this wallet in the entryPoint
    */
    function addDeposit() public payable {

        (bool req,) = address(_entryPoint).call{value : msg.value}("");
        require(req);
    }

    /**
     * withdraw value from the wallet's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner{
        _entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /// Social Recovery ///
    
    function addGuardians(bytes32[] calldata guardians) external onlyOwner {

        if(numberGuardians == 0 && guardians.length < 2) revert InvalidNumberOfGuardians();
        
        for(uint i = 0; i < guardians.length; i++) {

            bytes32 guardian = guardians[i];

            if(Guardians[guardian]) revert AlreadyGuardian(guardian);
            Guardians[guardian] = true;

            emit GuardianAdded(guardian);

        }

        numberGuardians += guardians.length;

        // make sure the threshold is at least 2
        if(threshold == 0) {
            threshold = 2;
        }

    }

    /**
    @dev Owner can remove guardians
    @param guardians Array of guardian hashs of guardians to be removed
    */
    function removeGuardians(bytes32[] calldata guardians) external onlyOwner {

        if(numberGuardians < guardians.length) revert GuardianRemovalLengthError();

        for(uint i = 0; i < guardians.length;) {

            bytes32 guardian = guardians[i];

            if(Guardians[guardian] == false) revert NotGuardian(guardian);

            Guardians[guardian] = false;

            emit GuardianRemoved(guardian);

            unchecked {
                ++i;
            }

        }

        numberGuardians -= guardians.length;

        // make sure the threshold isn't larger than the new number of guardians
        if(numberGuardians < threshold) {
            threshold = numberGuardians;
        }

        // cancel current recovery
        if(inRecovery) {
            inRecovery = false;
            emit RecoveryCancelled(msg.sender, recoveryRound);
            recoveryRound++;
        }

    }


    /**
    @dev Owner can update the number of guardians required to support a recovery before it succeeds
    @param _threshold New guardian threshold requirement
    */
    function updateThreshold(uint _threshold) external onlyOwner {

        if(_threshold > numberGuardians) revert InvalidThreshold();

        emit ThresholdChanged(_threshold, threshold);

        threshold = _threshold;
    }

    /**
    @dev Guardian can set a new owner of the wallet that they support, if enough guardians support the same owner than recovery to that owner can occur
    @param _newOwner The address of the new owner a guardian is supporting to gain control of the wallet
    */
    function recoverWallet(address _newOwner) onlyGuardian external {

        if(inRecovery == false) {

            inRecovery = true;
            emit RecoveryInitiated(msg.sender, _newOwner, recoveryRound);

        }

        guardiansRecovery[msg.sender] = RecoveryData(
            _newOwner,
            recoveryRound
        );

        emit RecoverySupported(msg.sender, _newOwner, recoveryRound);

    }

    /**
    @dev Owner can cancel a recovery attempt, invalidating guardians prior proposed recovery data
    */
    function cancelRecovery() onlyOwner onlyInRecovery external {
        inRecovery = false;
        emit RecoveryCancelled(msg.sender, recoveryRound);
        recoveryRound++;
    }

    /**
    @notice A Guardian can provide an array of valid guardians that have supported recovery to revocer the wallet to a new owner
    @param newOwner the new owner of the wallet
    @param guardians Address array of guardians that have supported this recovery
    */
    function executeRecovery(address newOwner, address[] calldata guardians) onlyGuardian onlyInRecovery external {

        if(threshold < guardians.length) revert InvalidNumberOfGuardiansToRecover();

        for(uint i = 0; i < guardians.length;) {

            address guardian = guardians[i];

            RecoveryData memory recovery = guardiansRecovery[guardian];

            if(recovery.proposedOwner != newOwner) revert InvalidOwner(guardian);

            if(recovery.recoveryRound != recoveryRound) revert InvalidRecoveryRound(guardian);

           
            for(uint j = 0; j < i;) {

                if(guardians[j] == guardian) revert GuardianUsedTwice(guardian);

                unchecked {
                    j++;
                }

            }

            unchecked {
                ++i;
            }

        }

        inRecovery = false;
        emit RecoveryExecuted(owner, newOwner, recoveryRound);
        owner = newOwner;
        recoveryRound++;

    }

    /// World ID ///

    /** 
    @dev Using world coin and a previously set _recoveryHash, this verifies if the request came from the original owner, allowing a recovery
    @param _newOwner User's input, the new owner of the wallet after recovery succeeds
    @param _root The of the Merkle tree, returned by the SDK.
    @param _recoveryHash The , preventing double signaling, returned by the SDK.
    @param _proof The zero knowledge proof that demostrates the claimer is registered with World ID, returned by the SDK.
    @dev Feel free to rename this method however you want! We've used `claim`, `verify` or `execute` in the past.
    */
    function recoverWalletWithWorldId(
        address _newOwner,
        uint256 _root,
        uint256 _recoveryHash,
        uint256[8] calldata _proof
    ) public {

        // check to see if the owner has allowed recovery with this method
        if(allowWorldIdRecovery == false) revert RecoveryNotAllowed();

        // make sure the recovery hash is the same as the owner set
        if (recoveryHash != _recoveryHash || _recoveryHash == 0) revert InvalidRecoveryHash();

        // then, we verify they're registered with WorldID, and the input they've provided is correct
        worldId.verifyProof(
            _root,
            groupId,
            abi.encodePacked(_newOwner).hashToField(),
            _recoveryHash,
            abi.encodePacked(WORLDID_ACTION_ID).hashToField(),
            _proof
        );

        emit RecoveryExecuted(owner, _newOwner, recoveryRound);

        if(inRecovery) {

            //increment the recovery round, invalidating any attempted recoveries
            recoveryRound++;
            //remove from recovery state
            inRecovery = false;

        } 

        //Set the owner as to the new owner provided, finishing the recovery process
        owner = _newOwner;

    }

    /**
    @dev Owner sets the recovery hash recieved from worldId, allowing them to recover wallet if keys are lost
    @param _recoveryHash Hash unique to worldId user and actionId, recieved from worldId
    */
    function setRecoveryHash(uint _recoveryHash) external onlyOwner {

        if(recoveryHash == _recoveryHash) revert InvalidRecoverySetting();

        recoveryHash = _recoveryHash;
        emit RecoveryHashSet(_recoveryHash);

        if(allowWorldIdRecovery == false) {
            allowWorldIdRecovery = true;
            emit WorldIdRecoverySet(true);
        }

    }

    /**
    @dev Owner sets the option to allow worldId to recover wallet
    @param _allowWorldIdRecovery Boolean to allow or dissallow woridId recovery
    */
    function setAllowWorldIdRecovery(bool _allowWorldIdRecovery) external onlyOwner {
        if(allowWorldIdRecovery == _allowWorldIdRecovery) revert InvalidRecoverySetting();
        allowWorldIdRecovery = _allowWorldIdRecovery;
        emit WorldIdRecoverySet(_allowWorldIdRecovery);
    }

    /// Super fluid ///

    function initSuperfluid(ISuperfluid host) external onlyOwner {

        if(address(cfaV1.host) != address(0)) revert SuperfluidAlreadyInitialized();
        //initialize InitData struct, and set equal to cfaV1
        cfaV1 = CFAv1Library.InitData(
        host,
        //here, we are deriving the address of the CFA using the host contract
        IConstantFlowAgreementV1(
            address(host.getAgreementClass(
                    keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
                ))
            )
        );
    }

    /**
    @dev allows a user to create a flow using their wallet
    */
    function createFlow(address receiver, ISuperToken token, int96 flowRate, bytes calldata userData) external onlyOwner {

        if(address(cfaV1.host) == address(0)) revert SuperfluidNotInitialized();
        cfaV1.createFlow(receiver, token, flowRate, userData);
    }
     /**
    @dev allows a user to update a flow using their wallet
    */
    function updateFlow(address receiver, ISuperToken token, int96 flowRate, bytes calldata userData) external onlyOwner {
         if(address(cfaV1.host) == address(0)) revert SuperfluidNotInitialized();
        cfaV1.updateFlow(receiver, token, flowRate, userData);
    }
    /**
    @dev allows a user to delete a flow using their wallet
    */
    function deleteFlow(address sender, address receiver, ISuperToken token, bytes calldata userData) external onlyOwner {
        if(address(cfaV1.host) == address(0)) revert SuperfluidNotInitialized();
        cfaV1.deleteFlow(sender, receiver, token, userData);
    }

    /// helper ///

    ///@dev Allows the wallet to receive nfts if safeTransfer is called to transfer to this wallet
    function onERC721Received(
        address caller,
        address from,
        uint256 tokenId,
        bytes memory
    ) public returns (bytes4) {
        // emit an event to help a potential frontend keep track of the nfts the dao posesses
        emit NftReceived(msg.sender, tokenId, from, caller);
        return this.onERC721Received.selector;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /// Events ///

    /// @notice emit when the allowing wallet recovery using world id is changed
    event WorldIdRecoverySet(bool value);

     /// @notice emit when the recovery hash required for world id wallet recovery is set
    event RecoveryHashSet(uint recoveryHash);

    /// @notice emit when the entryPoint changes
    event EntryPointChanged(address indexed oldEntryPoint, address indexed newEntryPoint);

    event NftReceived(address indexed contractAddress, uint256 indexed tokenId, address from, address caller);

    event ThresholdChanged(uint newThreshold, uint oldThreshold);

    event RecoverySupported(address guardian, address newOwner, uint256 indexed recoveryRound);
       
    event RecoveryCancelled(address guardian, uint256 indexed recoveryRound);

    event GuardianRemoved(bytes32 indexed guardian);

    event GuardianAdded(bytes32 indexed guardian);

    event RecoveryExecuted(address oldOwner, address newOwner, uint256 indexed recoveryRound);

    event RecoveryInitiated(address indexed guardian, address newOwner, uint256 indexed recoveryRound);

    /// Errors ///

    error NotGuardian(bytes32 guardian);

    error AlreadyGuardian(bytes32 guardian);

    error GuardianRemovalLengthError();

    error RecoveryNotAllowed();

    error InvalidRecoveryHash();

    error InvalidRecoverySetting();

    error InvalidNumberOfGuardians();

    error InvalidNumberOfGuardiansToRecover();

    error InvalidRecoveryRound(address guardian);

    error InvalidOwner(address guardian);

    error GuardianUsedTwice(address guardian);

    error InvalidThreshold();

    error SuperfluidAlreadyInitialized();

    error SuperfluidNotInitialized();


}