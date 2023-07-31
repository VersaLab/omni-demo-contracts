import { ethers } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollTestnetAddresses from "../../deploy/addresses/scrollTestnet.json";
import { generateWalletInitCode2 } from "../../test/utils";
import { estimateGasAndSendUserOpAndGetReceipt, generateUserOp } from "../utils/bundler";
import * as config from "../utils/config";

async function main() {
    const [signer] = await ethers.getSigners();
    const chainId = await signer.getChainId();
    const addr = await signer.getAddress();
    const salt = config.salt;
    const abiCoder = new ethers.utils.AbiCoder();
    const validatorInitdata = abiCoder.encode(["address"], [addr]);
    let bundlerURL, entryPointAddress, versaOmniFactoryAddress, ecdsaOmniValidatorAddress;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            entryPointAddress = polygonMumbaiAddresses.entryPoint;
            versaOmniFactoryAddress = polygonMumbaiAddresses.versaOmniFactory;
            ecdsaOmniValidatorAddress = polygonMumbaiAddresses.ecdsaOmniValidator;
            break;
        }
        case 534353: {
            bundlerURL = config.scrollTestnetBundlerURL;
            entryPointAddress = scrollTestnetAddresses.entryPoint;
            versaOmniFactoryAddress = scrollTestnetAddresses.versaOmniFactory;
            ecdsaOmniValidatorAddress = scrollTestnetAddresses.ecdsaOmniValidator;
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }

    // const initCode = "0x";
    // const walletAddress = "0xEF229c71de0991ca11aC1807B24402e1C9B673eB";
    const { initCode, walletAddress } = await generateWalletInitCode2({
        versaFacotryAddr: versaOmniFactoryAddress,
        salt: salt,
        sudoValidator: ecdsaOmniValidatorAddress,
        sudoValidatorInitData: validatorInitdata,
    });
    const wallet = await ethers.getContractAt("VersaOmniWallet", walletAddress);
    const callData = wallet.interface.encodeFunctionData("normalExecute", [
        signer.address,
        parseEther("0.0000001"),
        "0x",
        0,
    ]);
    const userOp = await generateUserOp({ signer, walletAddress, callData, initCode });
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
