import { ethers } from "hardhat";
import * as readline from "readline";
import { parseEther } from "ethers/lib/utils";
import lzChainIds from "./constants/lzChainIds.json";
import mumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollTestnetAddresses from "../../deploy/addresses/scrollTestnet.json";
import { generateWalletInitCode2 } from "../../test/utils";
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
    const addr = await signer1.getAddress();
    const addr2 = await signer2.getAddress();
    const abiCoder = new ethers.utils.AbiCoder();
    const salt = config.salt;
    const validatorInitdata = abiCoder.encode(["address"], [addr]);
    const validatorInitdata2 = abiCoder.encode(["address"], [addr2]);
    let bundlerURL,
        paymasterURL,
        entryPointAddress,
        versaOmniFactoryAddress,
        ecdsaValidator,
        ecdsaValidator2,
        dstChainId;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            paymasterURL = config.mumbaiPaymasterURL;
            entryPointAddress = mumbaiAddresses.entryPoint;
            versaOmniFactoryAddress = mumbaiAddresses.versaOmniFactory;
            ecdsaValidator = mumbaiAddresses.ecdsaValidator;
            ecdsaValidator2 = scrollTestnetAddresses.ecdsaValidator;
            dstChainId = lzChainIds["scroll-testnet"];
            break;
        }
        case 534353: {
            bundlerURL = config.scrollTestnetBundlerURL;
            paymasterURL = config.scrollTestnetPaymasterURL;
            entryPointAddress = scrollTestnetAddresses.entryPoint;
            versaOmniFactoryAddress = scrollTestnetAddresses.versaOmniFactory;
            ecdsaValidator = scrollTestnetAddresses.ecdsaValidator;
            ecdsaValidator2 = mumbaiAddresses.ecdsaValidator;
            dstChainId = lzChainIds["polygon-mumbai"];
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    let { _, walletAddress } = await generateWalletInitCode2({
        versaFacotryAddr: versaOmniFactoryAddress,
        salt: salt,
        sudoValidator: ecdsaValidator,
        sudoValidatorInitData: validatorInitdata,
    });
    console.log(walletAddress);
    const versaOmniFactory = await ethers.getContractAt("VersaOmniFactory", versaOmniFactoryAddress);
    const payload = await versaOmniFactory.getPayload(
        walletAddress,
        [ecdsaValidator2],
        [validatorInitdata],
        [1],
        [],
        [],
        [],
        []
    );
    let fee = await versaOmniFactory.estimateNativeFee(dstChainId, payload);
    fee = fee.add(parseEther("0.0001"));
    console.log(`(wei): ${fee} / (eth): ${ethers.utils.formatEther(fee)}`);
    await waitForEnter();
    const wallet = await ethers.getContractAt("VersaWallet", walletAddress);
    const data = versaOmniFactory.interface.encodeFunctionData("createAccountOnRemoteChain", [
        dstChainId,
        [ecdsaValidator2],
        [validatorInitdata],
        [1],
        [],
        [],
        [],
        [],
    ]);
    const callData = wallet.interface.encodeFunctionData("sudoExecute", [versaOmniFactoryAddress, fee, data, 0]);
    const userOp = await generateUserOp({ signer: signer1, walletAddress, callData });
    await estimateGasAndSendUserOpAndGetReceipt({
        bundlerURL,
        userOp,
        entryPoint: entryPointAddress,
        validator: ecdsaValidator,
        signers: [signer1],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
