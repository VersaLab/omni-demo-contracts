import hre, { ethers } from "hardhat";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollTestnetAddresses from "../../deploy/addresses/scrollTestnet.json";

async function main() {
    let [signer] = await ethers.getSigners();
    const chainId = await signer.getChainId();
    let localAddress, remoteAddress, remoteChainId;

    switch (chainId) {
        case 80001: {
            localAddress = polygonMumbaiAddresses["versaOmniFactory"];
            remoteAddress = scrollTestnetAddresses["versaOmniFactory"];
            remoteChainId = lzChainIds["scroll-testnet"];
            break;
        }
        case 534353: {
            localAddress = scrollTestnetAddresses["versaOmniFactory"];
            remoteAddress = polygonMumbaiAddresses["versaOmniFactory"];
            remoteChainId = lzChainIds["polygon-mumbai"];
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }

    const localContractInstance = await ethers.getContractAt("VersaOmniFactory", localAddress);
    const remoteAndLocal = hre.ethers.utils.solidityPack(["address", "address"], [remoteAddress, localAddress]);
    const isTrustedRemoteSet = await localContractInstance.isTrustedRemote(remoteChainId, remoteAndLocal);

    if (!isTrustedRemoteSet) {
        try {
            const tx = await (await localContractInstance.setTrustedRemote(remoteChainId, remoteAndLocal)).wait();
            console.log(`✅ [${hre.network.name}] setTrustedRemote(${remoteChainId}, ${remoteAndLocal})`);
            console.log(`txhash: ${tx.transactionHash}`);
        } catch (e) {
            if (e.error.message.includes("The chainId + address is already trusted")) {
                console.log("*source already set*");
            } else {
                console.log(`❌ [${hre.network.name}] setTrustedRemote(${remoteChainId}, ${remoteAndLocal})`);
                console.log(e);
            }
        }
    } else {
        console.log("*source already set*");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
