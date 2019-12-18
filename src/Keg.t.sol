pragma solidity >=0.5.12;

import "ds-test/test.sol";

import "./Keg.sol";

contract KegTest is DSTest {
    Keg keg;

    function setUp() public {
        address temp = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        keg = new Keg(temp, temp, temp, temp);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
