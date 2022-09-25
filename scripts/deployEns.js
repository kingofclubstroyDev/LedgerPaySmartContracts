const hre = require("hardhat");
const namehash = require('eth-ens-namehash');
const tld = "pay";
const ethers = hre.ethers;
const utils = ethers.utils;
const labelhash = (label) => utils.keccak256(utils.toUtf8Bytes(label))
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000";
const sapphire = require('@oasisprotocol/sapphire-paratime');


async function main() {

  // uncomment when deploying to saphire parachain
  // const signer0 = (await ethers.getSigners())[0];
  // const chainId = await signer0.getChainId();
  // const deployer = chainId in sapphire.NETWORKS ? sapphire.wrap(signer0) : signer0;
  // const provider = sapphire.wrap(deployer.provider); // We'll use this to read secrets as an unauthenticated party.

  ///

  const ENSRegistry = await ethers.getContractFactory("contracts/ens/ENSRegistry.sol:ENSRegistry", deployer)
  const FIFSRegistrar = await ethers.getContractFactory("FIFSRegistrar", deployer)
  const ReverseRegistrar = await ethers.getContractFactory("ReverseRegistrar", deployer)
  const PublicResolver = await ethers.getContractFactory("PublicResolver", deployer)
  const signers = await ethers.getSigners();
  const accounts = signers.map(s => s.address)

  
  let ens = await ENSRegistry.deploy()
  await ens.deployed()

  console.log("ens address: ", ens.address);

  const reverseRegistrar = await ReverseRegistrar.deploy(ens.address);
  await reverseRegistrar.deployed()

  console.log("reverseRegistrar address: ", reverseRegistrar.address);

  const resolver = await PublicResolver.deploy(ens.address, ZERO_ADDRESS, ZERO_ADDRESS, reverseRegistrar.address);
  await resolver.deployed()

  console.log("Resolver address: ", resolver.address);

  await setupResolver(ens, resolver, accounts)

  const registrar = await  FIFSRegistrar.deploy(ens.address, namehash.hash(tld));
  await registrar.deployed();

  console.log("registrar address: ", registrar.address);

  await setupRegistrar(ens, registrar);
 
  await setupReverseRegistrar(ens, registrar, reverseRegistrar, accounts);

  // wait for contracts to resolve before verifying
  await new Promise(r => setTimeout(r, 20000));

  await hre.run("verify:verify", {
    contract: "contracts/ens/ENSRegistry.sol:ENSRegistry",
    address: ens.address,
    constructorArguments: []
  })

  await hre.run("verify:verify", {
    address: reverseRegistrar.address,
    constructorArguments: [ens.address]
  })

  await hre.run("verify:verify", {
    address: resolver.address,
    constructorArguments: [ens.address, ZERO_ADDRESS, ZERO_ADDRESS, reverseRegistrar.address]
  })

  await hre.run("verify:verify", {
    address: registrar.address,
    constructorArguments: [ens.address, namehash.hash(tld)]
  })



};

async function setupResolver(ens, resolver, accounts) {
  const resolverNode = namehash.hash("resolver");
  const resolverLabel = labelhash("resolver");
  await ens.setSubnodeOwner(ZERO_HASH, resolverLabel, accounts[0]);
  console.log("set subnet");
 
  await ens.setResolver(resolverNode, resolver.address);
  console.log("set resolver");
 
  await resolver['setAddr(bytes32,address)'](resolverNode, resolver.address);
  console.log("set address");
 
}

async function setupRegistrar(ens, registrar) {
  await ens.setSubnodeOwner(ZERO_HASH, labelhash(tld), registrar.address);
  
}

async function setupReverseRegistrar(ens, registrar, reverseRegistrar, accounts) {
  console.log("reverse registrar")
  await ens.setSubnodeOwner(ZERO_HASH, labelhash("reverse"), accounts[0]);
  console.log("set sub owner");
  
  await ens.setSubnodeOwner(namehash.hash("reverse"), labelhash("addr"), reverseRegistrar.address);
  console.log("set node owner 2");
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });