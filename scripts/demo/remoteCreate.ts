import { ethers } from "hardhat";
import * as readline from "readline";
import { parseEther } from "ethers/lib/utils";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollTestnetAddresses from "../../deploy/addresses/scrollTestnet.json";
import { generateOmniWalletInitCode } from "../../test/utils";
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
    const [signer] = await ethers.getSigners();
    const chainId = await signer.getChainId();
    const addr = await signer.getAddress();
    const abiCoder = new ethers.utils.AbiCoder();
    const salt = config.salt;
    const validatorInitdata = abiCoder.encode(["address"], [addr]);
    let bundlerURL,
        entryPointAddress,
        versaOmniFactoryAddress,
        ecdsaOmniValidatorAddress,
        dstChainId,
        versaOmniWalletAddress;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            entryPointAddress = polygonMumbaiAddresses.entryPoint;
            versaOmniFactoryAddress = polygonMumbaiAddresses.versaOmniFactory;
            ecdsaOmniValidatorAddress = polygonMumbaiAddresses.ecdsaOmniValidator;
            dstChainId = lzChainIds["scroll-testnet"];
            versaOmniWalletAddress = polygonMumbaiAddresses.versaOmniWallet;
            break;
        }
        case 534353: {
            bundlerURL = config.scrollTestnetBundlerURL;
            entryPointAddress = scrollTestnetAddresses.entryPoint;
            versaOmniFactoryAddress = scrollTestnetAddresses.versaOmniFactory;
            ecdsaOmniValidatorAddress = scrollTestnetAddresses.ecdsaOmniValidator;
            dstChainId = lzChainIds["polygon-mumbai"];
            versaOmniWalletAddress = scrollTestnetAddresses.versaOmniWallet;
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    const versaOmniFactory = await ethers.getContractAt("VersaOmniFactory", versaOmniFactoryAddress);
    let fee = await versaOmniFactory.estimateRemoteCreateFee(
        versaOmniWalletAddress,
        dstChainId,
        [80001, 534353],
        [10109, 10170]
    );
    // fee = fee.add(parseEther("0.0001"));
    console.log(`(wei): ${fee} / (eth): ${ethers.utils.formatEther(fee)}`);
    await waitForEnter();
    const wallet = await ethers.getContractAt("VersaOmniWallet", versaOmniWalletAddress);
    const data = versaOmniFactory.interface.encodeFunctionData("createAccountOnRemoteChain", [
        dstChainId,
        [80001, 534353],
        [10109, 10170],
    ]);
    const callData = wallet.interface.encodeFunctionData("sudoSpecificExecute", [
        versaOmniFactoryAddress,
        fee,
        data,
        0,
    ]);
    const userOp = await generateUserOp({ signer: signer, walletAddress: versaOmniWalletAddress, callData });
    await estimateGasAndSendUserOpAndGetReceipt({
        bundlerURL,
        userOp,
        entryPoint: entryPointAddress,
        validator: ecdsaOmniValidatorAddress,
        signers: [signer],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
