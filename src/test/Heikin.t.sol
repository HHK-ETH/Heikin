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

contract HeikinTest is Test {
    BentoBoxV1 bentobox;
    Heikin heikin;
    Token weth;
    PriceAggregator wethOracle;
    Token usdc;
    PriceAggregator usdcOracle;
    ConstantProductPool weth_usdcPool;

    function setUp() public {
        //basic setup
        weth = new Token("WETH", "WETH", 18, 100 * 10**18);
        wethOracle = new PriceAggregator(8);
        usdc = new Token("USDC", "USDC", 6, 10_000 * 10**6);
        usdcOracle = new PriceAggregator(8);
        bentobox = new BentoBoxV1(IERC20(address(weth)));
        heikin = new Heikin(address(bentobox));

        //Trident setup
        MasterDeployer masterDeployer = new MasterDeployer(
            30,
            address(1),
            address(bentobox)
        );
        ConstantProductPoolFactory constantProductPoolFactory;
        TridentRouter trident;
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
        assertEq(heikin.getDcaData(newDcaId).owner, address(this));
    }
}
