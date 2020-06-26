pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "lib/dss-interfaces/src/Interfaces.sol";

import "./Keg.sol";
import {DssSpell, SpellAction} from "./Keg-Spell.sol";

contract Hevm { function warp(uint) public; }

contract KegTest is DSTest, DSMath {
    Hevm hevm;

    DssSpell spell;

    address constant public DAI      = 0x78E8E1F59D80bE6700692E2aAA181eAb819FA269;
    address constant public DAI_JOIN = 0x42497e715a1e793a65E9c83FE813AfC677952e16; // Have not done rely/deny
    address constant public MCD_VOW  = 0xBFE7af74255c660e187758D23A08B4D5074252C7;
    address constant public MCD_VAT  = 0x11eFdA5E32683555a508c30B1100063b4335FC3E;
    address constant public USER     = 0x57D37c790DDAA0b82e3DEb291DbDd8556c94F1f1;

    MKRAbstract       gov = MKRAbstract(0x8CA90018a8D759F68DD6de3d4fc58d37602aac78);
    DSChiefAbstract chief = DSChiefAbstract(0x8C67F07CBe3c0dBA5ECd5c1804341703458A2e8A);
    DSPauseAbstract pause = DSPauseAbstract(0xCE8B162F99eFB2dFc0A448A8D7Ed3218B5919ED1);
    Keg               keg = Keg(0x66eFe121646FE881b1c950BFC855E506696fA773);

    uint256 constant public THOUSAND = 10**3;
    uint256 constant public MILLION  = 10**6;
    uint256 constant public WAD      = 10**18;
    uint256 constant public RAY      = 10**27;
    uint256 constant public RAD      = 10**45;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        spell = new DssSpell();
    }

    function vote() private {
        if (chief.hat() != address(spell)) {
            gov.approve(address(chief), uint256(-1));
            chief.lock(sub(gov.balanceOf(address(this)), 1 ether));

            assertTrue(!spell.done());

            address[] memory yays = new address[](1);
            yays[0] = address(spell);

            chief.vote(yays);
            chief.lift(address(spell));
        }
        assertEq(chief.hat(), address(spell));
    }

    function scheduleWaitAndCast() public {
        spell.schedule();
        hevm.warp(now + pause.delay());
        spell.cast();
    }

    function testSpellIsCast() public {
        // Test description
        string memory description = new SpellAction().description();
        assertTrue(bytes(description).length > 0);

        vote();
        scheduleWaitAndCast();
        assertTrue(spell.done());
    }


    function test_keg_deploy() public {
        assertEq(address(keg.vat()),  MCD_VAT);
        assertEq(address(keg.join()), DAI_JOIN);
        assertEq(address(keg.dai()),  DAI);
        assertEq(keg.vow(),  MCD_VOW);
    }

    function test_brew() public {
        vote();
        scheduleWaitAndCast();
        assertTrue(spell.done());
        address[] memory users = new address[](1);
        users[0] = USER;
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1 ether;
        keg.brew(users, amts);
    }
}
