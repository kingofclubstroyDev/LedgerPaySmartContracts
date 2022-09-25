import { ethers } from "hardhat";
const hre = require("hardhat");

async function main() {

    //set entrypoing address
    const entryPointAddress = ""

    // ser wallet logic implementation address
    const walletImplementationAddress = "";

    // set wallet owner address
    const walletOwnerAddress = "";

    // set world id address
    const worldIdAddress = "";

    const [deployer] = await ethers.getSigners();
  
    console.log("Deploying contracts with the account:", deployer.address);
  
    console.log("Account balance:", (await deployer.getBalance()).toString());

    let ProxyFactory = await ethers.getContractFactory("LedgerPayWalletProxy");

    let proxyWallet = await ProxyFactory.deploy(entryPointAddress, walletOwnerAddress, walletImplementationAddress, worldIdAddress)

    console.log("proxy wallet address = ", proxyWallet.address);

    // wait for blocks to settle
    await new Promise(r => setTimeout(r, 20000));

    await hre.run("verify:verify", {
      address: proxyWallet.address,
      constructorArguments: [entryPointAddress, walletOwnerAddress, walletImplementationAddress, worldIdAddress]
    })

  }
  
main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exit(1);
});