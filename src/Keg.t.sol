pragma solidity >=0.5.12;

import "ds-test/test.sol";

import "./Keg.sol";
import {DssSpell, SpellAction} from "./Keg-Spell.sol";

contract Hevm { function warp(uint) public; }

contract KegTest is DSTest {
    Keg keg;
    Hevm hevm;

    DssSpell spell;

    address constant public DAI      = 0xD657D4c62cBcC9E9EF90076A04dFe2bDBDed3328;
    address constant public DAI_JOIN = 0xF4Acaab5815B970c98fbe1c86793299409B9C869; // Have not done rely/deny
    address constant public MCD_VOW  = 0x0E53EA0217E77b06B924F141A1f433c51e0AE9C1;
    address constant public MCD_VAT  = 0x91c46788E3DE271a559a8140F65817aF8F5832D4;
    address constant public USER     = 0x57D37c790DDAA0b82e3DEb291DbDd8556c94F1f1;

    MKRAbstract              gov = MKRAbstract(0xC978a2b299Ee2211dcA136fb81449D61a09C2eA1);
    DSChiefAbstract        chief = DSChiefAbstract(0xbBFFC76e94B34F72D96D054b31f6424249c1337d);



    uint256 constant public THOUSAND = 10**3;
    uint256 constant public MILLION  = 10**6;
    uint256 constant public WAD      = 10**18;
    uint256 constant public RAY      = 10**27;
    uint256 constant public RAD      = 10**45;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        spell = KOVAN_SPELL != address(0) ? DssSpell(KOVAN_SPELL) : new DssSpell();
        keg = new Keg(MCD_VAT, DAI_JOIN, DAI, MCD_VOW);
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

    function test_keg_deploy() public {
        assertEq(address(keg.vat()),  MCD_VAT);
        assertEq(address(keg.join()), DAI_JOIN);
        assertEq(address(keg.dai()),  DAI);
        assertEq(keg.vow(),  MCD_VOW);
    }

    function test_pour_brew() public {
        vote();
        scheduleWaitAndCast();
        assertTrue(spell.done());
        address[] memory users = new address[](1);
        users[0] = USER;
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1 ether;
        keg.pourbrew(users, amts);
    }
}
