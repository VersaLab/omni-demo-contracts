import { ethers } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import fs from "fs";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollSepoliaAddresses from "../../deploy/addresses/scrollSepolia.json";
import { generateOmniWalletInitCode } from "../../test/utils";
import { estimateGasAndSendUserOpAndGetReceipt, generateUserOp } from "../utils/bundler";
import * as config from "../utils/config";

async function main() {
    const [signer1, signer2] = await ethers.getSigners();
    const chainId = await signer1.getChainId();
    const addr = await signer1.getAddress();
    const salt = config.salt;
    const abiCoder = new ethers.utils.AbiCoder();
    const validatorInitdata = abiCoder.encode(["address"], [addr]);
    let bundlerURL, entryPointAddress, versaOmniFactoryAddress, ecdsaOmniValidatorAddress, versaOmniWalletAddress;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            entryPointAddress = polygonMumbaiAddresses.entryPoint;
            versaOmniFactoryAddress = polygonMumbaiAddresses.versaOmniFactory;
            ecdsaOmniValidatorAddress = polygonMumbaiAddresses.ecdsaOmniValidator;
            versaOmniWalletAddress = polygonMumbaiAddresses.versaOmniWallet;
            break;
        }
        case 534351: {
            bundlerURL = config.scrollSepoliaBundlerURL;
            entryPointAddress = scrollSepoliaAddresses.entryPoint;
            versaOmniFactoryAddress = scrollSepoliaAddresses.versaOmniFactory;
            ecdsaOmniValidatorAddress = scrollSepoliaAddresses.ecdsaOmniValidator;
            versaOmniWalletAddress = scrollSepoliaAddresses.versaOmniWallet;
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }

    // const initCode = "0x";
    // const walletAddress = versaOmniWalletAddress;

    const { initCode, walletAddress } = await generateOmniWalletInitCode({
        versaFacotryAddr: versaOmniFactoryAddress,
        salt: salt,
        sudoValidator: ecdsaOmniValidatorAddress,
        sudoValidatorInitData: validatorInitdata,
    });
    polygonMumbaiAddresses.versaOmniWallet = walletAddress;
    scrollSepoliaAddresses.versaOmniWallet = walletAddress;
    fs.writeFileSync("deploy/addresses/polygonMumbai.json", JSON.stringify(polygonMumbaiAddresses, null, "\t"), "utf8");
    fs.writeFileSync("deploy/addresses/scrollSepolia.json", JSON.stringify(scrollSepoliaAddresses, null, "\t"), "utf8");

    const wallet = await ethers.getContractAt("VersaOmniWallet", walletAddress);
    const callData = wallet.interface.encodeFunctionData("normalExecute", [
        signer1.address,
        parseEther("0.0000001"),
        "0x",
        0,
    ]);

    const userOp = await generateUserOp({ signer: signer1, walletAddress, callData, initCode });
    await estimateGasAndSendUserOpAndGetReceipt({
        bundlerURL,
        userOp,
        entryPoint: entryPointAddress,
        validator: ecdsaOmniValidatorAddress,
        signers: [signer1],
    });

    // const userOp = await generateUserOp({ signer: signer1, walletAddress, callData, initCode });
    // await estimateGasAndSendUserOpAndGetReceipt({
    //     bundlerURL,
    //     userOp,
    //     entryPoint: entryPointAddress,
    //     validator: ecdsaOmniValidatorAddress,
    //     signers: [signer2],
    // });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
