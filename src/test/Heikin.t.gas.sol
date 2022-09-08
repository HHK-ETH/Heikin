// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {BentoBoxV1, IERC20} from "./../flat/Bentobox.sol";
import {ConstantProductPoolFactory, ConstantProductPool} from "./../flat/ConstantPoolFactory.sol";
import {MasterDeployer} from "./../flat/MasterDeployer.sol";
import {TridentRouter} from "./../flat/Trident.sol";
import {Token} from "./../mocks/Token.sol";
import {PriceAggregator} from "./../mocks/PriceAggregator.sol";
import {Heikin} from "./../Heikin.sol";

contract HeikinGasTest is Test {
    BentoBoxV1 bentobox;
    Heikin heikin;
    Token weth;
    PriceAggregator wethOracle;
    Token usdc;
    PriceAggregator usdcOracle;

    function setUp() public {
        weth = new Token("WETH", "WETH", 18, 100 * 10**18);
        wethOracle = new PriceAggregator(8);
        usdc = new Token("USDC", "USDC", 6, 10_000 * 10**6);
        usdcOracle = new PriceAggregator(8);
        bentobox = new BentoBoxV1(IERC20(address(weth)));
        heikin = new Heikin(address(bentobox));
    }

    function testCreateDca() public {
        uint256 newDcaId = heikin.createDCA(
            address(this),
            address(usdc),
            address(weth),
            address(usdcOracle),
            address(wethOracle),
            24 * 3600,
            12,
            10 * 10**6
        );
    }

    function testGetDca() public {
        heikin.getDcaData(0);
    }
}
