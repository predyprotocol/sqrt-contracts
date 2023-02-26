// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract TestControllerAddPair is TestController {
    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestController.setUp();

        controller.setOperator(user1);
    }

    function testSetOperator() public {
        vm.prank(user1);
        controller.setOperator(user2);

        assertEq(controller.operator(), user2);
    }

    function testCannotSetOperator_IfCallerIsNotOperator() public {
        vm.prank(user2);
        vm.expectRevert(bytes("C1"));
        controller.setOperator(user2);
    }

    function testCannotSetOperator_IfAddressIsZero() public {
        vm.prank(user1);
        vm.expectRevert();
        controller.setOperator(address(0));
    }
}
