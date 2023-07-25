import { ethers } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import mumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
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
    let bundlerURL, paymasterURL, entryPointAddress, versaOmniFactoryAddress, ecdsaValidator;
    switch (chainId) {
        case 80001: {
            bundlerURL = config.mumbaiBundlerURL;
            paymasterURL = config.mumbaiPaymasterURL;
            entryPointAddress = mumbaiAddresses.entryPoint;
            versaOmniFactoryAddress = mumbaiAddresses.versaOmniFactory;
            ecdsaValidator = mumbaiAddresses.ecdsaValidator;
            break;
        }
        case 534353: {
            bundlerURL = config.scrollTestnetBundlerURL;
            paymasterURL = config.scrollTestnetPaymasterURL;
            entryPointAddress = scrollTestnetAddresses.entryPoint;
            versaOmniFactoryAddress = scrollTestnetAddresses.versaOmniFactory;
            ecdsaValidator = scrollTestnetAddresses.ecdsaValidator;
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    // const { initCode, walletAddress } = await generateWalletInitCode2({
    //     versaFacotryAddr: versaOmniFactoryAddress,
    //     salt: salt,
    //     sudoValidator: ecdsaValidator,
    //     sudoValidatorInitData: validatorInitdata,
    // });
    const initCode = "0x";
    const walletAddress = "0xe88f293a7c959382baac4916d2fea3723dae46cb";
    const wallet = await ethers.getContractAt("VersaWallet", walletAddress);
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
        validator: ecdsaValidator,
        signers: [signer],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
