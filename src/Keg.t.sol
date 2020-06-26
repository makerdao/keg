pragma solidity >=0.5.12;

import "ds-test/test.sol";

import "./Keg.sol";

contract Hevm { function warp(uint) public; }

contract KegTest is DSTest {
    Keg keg;
    Hevm hevm;

    address constant public DAI      = 0xD657D4c62cBcC9E9EF90076A04dFe2bDBDed3328;
    address constant public DAI_JOIN = 0xaC7c532eDdde7f7a025C62415959A07Ea9d83da8;
    address constant public MCD_VOW  = 0x0F4Cbe6CBA918b7488C26E29d9ECd7368F38EA3b;
    address constant public MCD_VAT  = 0xbA987bDB501d131f766fEe8180Da5d81b34b69d9;
    address constant public USER     = 0x57D37c790DDAA0b82e3DEb291DbDd8556c94F1f1;

    uint256 constant public THOUSAND = 10**3;
    uint256 constant public MILLION  = 10**6;
    uint256 constant public WAD      = 10**18;
    uint256 constant public RAY      = 10**27;
    uint256 constant public RAD      = 10**45;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        keg = new Keg(MCD_VAT, DAI_JOIN, DAI, MCD_VOW);
    }

    function test_keg_deploy() public {
        assertEq(address(keg.vat()),  MCD_VAT);
        assertEq(address(keg.join()), DAI_JOIN);
        assertEq(address(keg.dai()),  DAI);
        assertEq(keg.vow(),  MCD_VOW);
    }

    function test_pour_brew() public {
        address[] memory users = [USER];
        keg.pourbrew(users, [1 ether]);
    }
}
