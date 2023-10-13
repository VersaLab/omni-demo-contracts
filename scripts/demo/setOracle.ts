import hre, { ethers } from "hardhat";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollAlphaAddresses from "../../deploy/addresses/scrollAlpha.json";

async function main() {
    let [signer] = await ethers.getSigners();
    const chainId = await signer.getChainId();
    let contractAddress, dstChainId, sendOracle, receiveOracle;
    switch (chainId) {
        case 80001: {
            contractAddress = polygonMumbaiAddresses["versaOmniFactory"];
            dstChainId = lzChainIds["scroll-alpha"];
            sendOracle = "0xAeC5E56217a963BDe38a3b6e0C3Cb5E864450C86";
            receiveOracle = "0xAeC5E56217a963BDe38a3b6e0C3Cb5E864450C86";
            break;
        }
        case 534353: {
            contractAddress = scrollAlphaAddresses["versaOmniFactory"];
            dstChainId = lzChainIds["polygon-mumbai"];
            sendOracle = "0x3aCAAf60502791D199a5a5F0B173D78229eBFe32";
            receiveOracle = "0x3aCAAf60502791D199a5a5F0B173D78229eBFe32";
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    const contractInstance = await ethers.getContractAt("VersaOmniFactory", contractAddress);
    console.log(`[${hre.network.name}] VersaOmniFactory Address: ${contractAddress}`);
    const tx = await (await contractInstance.setOracle(dstChainId, sendOracle, receiveOracle)).wait();
    console.log(`✅ Set Oracle: [${sendOracle}][${receiveOracle}] for src (${chainId}) -> dst (${dstChainId})`);
    console.log(`txhash: ${tx.transactionHash}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
