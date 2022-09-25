# Ledger Pay Smart contracts

This project implements erc4337 account abstraction built on eth-infinitism's entrypoint and wallet contracts. See https://github.com/eth-infinitism/account-abstraction.

The goal is to allow gas abstraction with users wallets, while they maintain full control over their funds and private keys. The LedgerPaymaster.sol contract is our projects wallet that allows the owner of the wallet to either call it directly to execute function, or submit a transaction, to a separape mem pool that gets bundled and sent through the EntryPoint.sol contract. This allows a paymaster to be selected, each paying the gas fee of a users transaction, but setting the rules on how they will be compensated. This allows transactions to be paid in erc20 tokens, or however a paymaster sees fit. In our implementation the LedgerPaymaster contract does not charge gas, and pays for the transactions for free, but has the ability to only accept requests that have been signed by a trusted wallet, allowing us to filter which transactions we will pay for in our backend. 

The LedgerPay wallet also implements additional features:

    Social Recovery:
        the owner of a wallet can set "guardians", which are wallet addresses (hashed) of people they trust, which can recover the wallet, transfering ownership to another address in the case the owner loses their keys. Ideally the guardians don't know eachother, and can't coordinate to steal the wallet. This is currently an opt in feature, and requires at least 2 trusted guardians to set up.

    World Id Recovery:

        The owner of a wallet can setup an account with world id, and verify with our action id and any signal to get the nullifier hash unique to that user and our apps action id. If they choose they can set the recovery hash on the wallet to opt into wallet recovery via world id. If they lose access to their private key, they can verify again with world id and our action id, while inputing their a new address that they want to recover ownership to as the signal. They can then call recoverWalletWithWorldId with the proper proof and if it passes, we know it was the original owner that generated the proof, so ownership transfers to the new owner address passed in (signal). 

        Note: this is only functional for our wallets deployed on polygon

    Superfluid:

        This wallet has integrated superfluid interactions, to make it easier to create/update/delete flows directly on the wallet contact

    Proxy factory:

        For each chain the logic bytecode is only deployed once, and each wallet contract deployed is a proxy contract that delegates the logic from the wallet implementation. This lowers the gas fees on each wallet significantly.

    ENS:

        We have deployed our own private ens using the ttl ".pay" so users can more easily manage their and their contracts wallet addresses, by dealing with human readable ens domains

Checkout deployments.txt for all smart contract deployments across the chains: polygon mainnet, optimism mainnet, oasis saphire parachain testnet, and cronos testnet 




