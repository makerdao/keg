pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./Keg.sol";

contract KegTest is DSTest {
    Keg keg;

    function setUp() public {
        keg = new Keg();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
