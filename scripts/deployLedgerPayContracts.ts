import { ethers } from "hardhat";
import { LedgerPayWallet, LedgerPaymaster, LedgerPaymaster__factory, Create2Factory__factory } from "../typechain-types";
import { EntryPoint } from "../typechain-types/contracts/EntryPoint";
const hre = require("hardhat");
import { arrayify, defaultAbiCoder, hexConcat, parseEther } from 'ethers/lib/utils'

import { Create2Factory } from './Create2Factory'
import { getContractFactory } from "@nomiclabs/hardhat-ethers/types";
import * as sapphire from '@oasisprotocol/sapphire-paratime';

async function main() {

  /// if deploying on saphire parachain, deployer is wrapped to this
  // const signer0 = (await ethers.getSigners())[0];
  // const chainId = await signer0.getChainId();
  // const deployer = chainId in sapphire.NETWORKS ? sapphire.wrap(signer0) : signer0;
  // const provider = sapphire.wrap(deployer.provider!); // We'll use this to read secrets as an unauthenticated party.

    let entryPoint : EntryPoint;
    const [deployer] = await ethers.getSigners();

    let paymasterStake = 1;
    let unstakeDelaySecs = 1;

    let paymaster: LedgerPaymaster

    let create2FactoryAddress = "0xce0042B868300000d44A59004Da54A005ffdcf9f"


    //TODO: change this if we can use defualt create2 factory address
    const deployFactory = false;

    if(deployFactory) {

      // let factory = await new Create2Factory__factory(deployer).deploy();

      let FACTORY = await ethers.getContractFactory("create2Factory", deployer);

      let factory = await FACTORY.deploy();

      console.log("factory deployed, address = ", factory.address);

      create2FactoryAddress = factory.address;

    }

    entryPoint = await (await ethers.getContractFactory("contracts/EntryPoint.sol:EntryPoint", deployer)).deploy(create2FactoryAddress, paymasterStake, unstakeDelaySecs) as EntryPoint

    await entryPoint.deployed();

    console.log("entryPoint address = ", entryPoint.address);

    paymaster = await new LedgerPaymaster__factory(deployer).deploy(entryPoint.address, deployer.address)

    await paymaster.deployed();

    console.log("paymaster address = ", paymaster.address)

    await paymaster.addStake(0, { value: parseEther('0.01') })
    //await new Promise(r => setTimeout(r, 10000));
    await entryPoint.depositTo(paymaster.address, { value: parseEther('0.01') })
    await new Promise(r => setTimeout(r, 10000));

  
    const WalletImplementation = await ethers.getContractFactory("LedgerPayWallet", deployer);
    const walletImplementation = await WalletImplementation.deploy() as LedgerPayWallet;

    await walletImplementation.deployed();

    console.log("Implementation address:", walletImplementation.address);

    
    //make sure to call implementation with bogus values to prevent malicious attacks on the implementation logic
    await walletImplementation.initialize(ethers.constants.AddressZero, ethers.constants.AddressZero, ethers.constants.AddressZero)

    // wait for the contracts to settle before verifying
    await new Promise(r => setTimeout(r, 20000));

    await hre.run("verify:verify", {
      address: walletImplementation.address,
      constructorArguments: []
    })

    await hre.run("verify:verify", {
      address: entryPoint.address,
      constructorArguments: [create2FactoryAddress, 1, 1]
    })

    await hre.run("verify:verify", {
      address: paymaster.address,
      constructorArguments: [entryPoint.address, deployer.address]
    })


  }
  
main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exit(1);
});