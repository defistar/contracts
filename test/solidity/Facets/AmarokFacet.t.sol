// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import { ILiFi, LibSwap, LibAllowList, TestBaseFacet, console, ERC20 } from "../utils/TestBaseFacet.sol";
import { AmarokFacet } from "lifi/Facets/AmarokFacet.sol";
import { IConnextHandler } from "lifi/Interfaces/IConnextHandler.sol";
import { OnlyContractOwner, InvalidConfig, NotInitialized, AlreadyInitialized, InvalidAmount } from "src/Errors/GenericErrors.sol";

// Stub AmarokFacet Contract
contract TestAmarokFacet is AmarokFacet {
    constructor(IConnextHandler _connextHandler, uint32 _srcChainDomain)
        AmarokFacet(_connextHandler, _srcChainDomain)
    {}

    function addDex(address _dex) external {
        LibAllowList.addAllowedContract(_dex);
    }

    function setFunctionApprovalBySignature(bytes4 _signature) external {
        LibAllowList.addAllowedSelector(_signature);
    }
}

contract AmarokFacetTest is TestBaseFacet {
    address internal constant CONNEXT_HANDLER = 0x01EdE4Fdf8CF7Ef9942a935305C3145f8dAa180A;
    address internal constant CONNEXT_HANDLER2 = 0x2b501381c6d6aFf9238526352b1c7560Aa35A7C5;
    uint32 internal constant DSTCHAIN_DOMAIN_GOERLI = 1735356532;
    uint32 internal constant DSTCHAIN_DOMAIN_MAINNET = 6648936;
    uint32 internal constant DSTCHAIN_DOMAIN_POLYGON = 1886350457;
    // -----

    TestAmarokFacet internal amarokFacet;
    AmarokFacet.AmarokData internal amarokData;

    function setUp() public {
        // set custom block no for mainnet forking
        customBlockNumberForForking = 16176320;

        initTestBase();

        amarokFacet = new TestAmarokFacet(IConnextHandler(CONNEXT_HANDLER2), DSTCHAIN_DOMAIN_MAINNET);
        bytes4[] memory functionSelectors = new bytes4[](5);
        functionSelectors[0] = amarokFacet.startBridgeTokensViaAmarok.selector;
        functionSelectors[1] = amarokFacet.swapAndStartBridgeTokensViaAmarok.selector;
        functionSelectors[2] = amarokFacet.setAmarokDomain.selector;
        functionSelectors[3] = amarokFacet.addDex.selector;
        functionSelectors[4] = amarokFacet.setFunctionApprovalBySignature.selector;

        addFacet(diamond, address(amarokFacet), functionSelectors);
        amarokFacet = TestAmarokFacet(address(diamond));
        amarokFacet.addDex(address(uniswap));
        amarokFacet.setFunctionApprovalBySignature(uniswap.swapExactTokensForTokens.selector);
        amarokFacet.setFunctionApprovalBySignature(uniswap.swapETHForExactTokens.selector);

        setFacetAddressInTestBase(address(amarokFacet), "AmarokFacet");

        // label addresses for better call traces
        vm.label(CONNEXT_HANDLER, "CONNEXT_HANDLER");

        // set Amarok domain mappings
        amarokFacet.setAmarokDomain(1, DSTCHAIN_DOMAIN_MAINNET);
        amarokFacet.setAmarokDomain(137, DSTCHAIN_DOMAIN_POLYGON);

        // adjust bridgeData
        bridgeData.bridge = "amarok";
        bridgeData.destinationChainId = 137;

        // produce valid AcrossData
        amarokData = AmarokFacet.AmarokData({ callData: "", relayerFee: 0, slippageTol: 9995 });

        // make sure relayerFee is sent with every transaction
        addToMessageValue = 1 * 10**15;
    }

    function initiateBridgeTxWithFacet(bool isNative) internal override {
        if (isNative) {
            amarokFacet.startBridgeTokensViaAmarok{ value: bridgeData.minAmount }(bridgeData, amarokData);
        } else {
            amarokFacet.startBridgeTokensViaAmarok(bridgeData, amarokData);
        }
    }

    function initiateSwapAndBridgeTxWithFacet(bool isNative) internal override {
        if (isNative) {
            amarokFacet.swapAndStartBridgeTokensViaAmarok{ value: swapData[0].fromAmount }(
                bridgeData,
                swapData,
                amarokData
            );
        } else {
            amarokFacet.swapAndStartBridgeTokensViaAmarok(bridgeData, swapData, amarokData);
        }
    }

    function testBase_CanBridgeNativeTokens() public override {
        // facet does not support bridging of native assets
    }

    function testBase_CanSwapAndBridgeNativeTokens() public override {
        // facet does not support bridging of native assets
    }
}
