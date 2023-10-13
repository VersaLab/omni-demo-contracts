import { ethers } from "hardhat";
import * as readline from "readline";
import { parseEther } from "ethers/lib/utils";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollAlphaAddresses from "../../deploy/addresses/scrollAlpha.json";
import { estimateGasAndSendUserOpAndGetReceipt, generateUserOp } from "../utils/bundler";
import * as config from "../utils/config";

function waitForEnter() {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });

    return new Promise((resolve) => {
        rl.question("按下回车键继续...", () => {
            rl.close();
            resolve();
        });
    });
}

async function main() {
    const [signer1, signer2] = await ethers.getSigners();
    const chainId = await signer1.getChainId();
    let bundlerURL, entryPointAddress, ecdsaOmniValidatorAddress, dstChainId, versaOmniWalletAddress;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            entryPointAddress = polygonMumbaiAddresses.entryPoint;
            ecdsaOmniValidatorAddress = polygonMumbaiAddresses.ecdsaOmniValidator;
            dstChainId = lzChainIds["scroll-alpha"];
            versaOmniWalletAddress = polygonMumbaiAddresses.versaOmniWallet;
            break;
        }
        case 534353: {
            bundlerURL = config.scrollAlphaBundlerURL;
            entryPointAddress = scrollAlphaAddresses.entryPoint;
            ecdsaOmniValidatorAddress = scrollAlphaAddresses.ecdsaOmniValidator;
            dstChainId = lzChainIds["polygon-mumbai"];
            versaOmniWalletAddress = scrollAlphaAddresses.versaOmniWallet;
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    const ecdsaValidator = await ethers.getContractAt("ECDSAOmniValidator", ecdsaOmniValidatorAddress);
    const wallet = await ethers.getContractAt("VersaOmniWallet", versaOmniWalletAddress);
    const data = ecdsaValidator.interface.encodeFunctionData("setSigner", [await signer2.getAddress()]);
    const callData = wallet.interface.encodeFunctionData("batchSudoSyncExecute", [
        [ecdsaOmniValidatorAddress],
        [0],
        [data],
        [0],
    ]);
    const userOp = await generateUserOp({ signer: signer1, walletAddress: versaOmniWalletAddress, callData });
    await estimateGasAndSendUserOpAndGetReceipt({
        bundlerURL,
        userOp,
        entryPoint: entryPointAddress,
        validator: ecdsaOmniValidatorAddress,
        signers: [signer1],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
