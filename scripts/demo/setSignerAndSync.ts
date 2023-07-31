import { ethers } from "hardhat";
import * as readline from "readline";
import { parseEther } from "ethers/lib/utils";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollTestnetAddresses from "../../deploy/addresses/scrollTestnet.json";
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
    let bundlerURL, entryPointAddress, ecdsaOmniValidatorAddress, dstChainId;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            entryPointAddress = polygonMumbaiAddresses.entryPoint;
            ecdsaOmniValidatorAddress = polygonMumbaiAddresses.ecdsaOmniValidator;
            dstChainId = lzChainIds["scroll-testnet"];
            break;
        }
        case 534353: {
            bundlerURL = config.scrollTestnetBundlerURL;
            entryPointAddress = scrollTestnetAddresses.entryPoint;
            ecdsaOmniValidatorAddress = scrollTestnetAddresses.ecdsaOmniValidator;
            dstChainId = lzChainIds["polygon-mumbai"];
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    const walletAddress = "0xda14c2758463559550ea6fb3322bc50f5e4c7fed";
    const ecdsaValidator = await ethers.getContractAt("ECDSAOmniValidator", ecdsaOmniValidatorAddress);
    const wallet = await ethers.getContractAt("VersaOmniWallet", walletAddress);
    const data = ecdsaValidator.interface.encodeFunctionData("setSigner", [await signer2.getAddress()]);
    const callData = wallet.interface.encodeFunctionData("batchSudoSyncExecute", [
        [ecdsaOmniValidatorAddress],
        [0],
        [data],
        [0],
    ]);
    console.log(callData);
    const userOp = await generateUserOp({ signer: signer1, walletAddress, callData });
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
