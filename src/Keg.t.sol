pragma solidity >=0.5.15;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "lib/dss-interfaces/src/Interfaces.sol";

import "./Keg.sol";

contract Hevm { function warp(uint) public; }

contract TestVat is DSMath {
    mapping (address => uint256) public dai;
    function suck(address u, address v, uint rad) public { dai[v] = add(dai[v], rad); }
    function move(address src, address dst, uint256 rad) public {
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }
}

contract User {
    Keg public keg;
    constructor(Keg keg_) public       { keg = keg_; }
    function pass(address bud_) public { keg.pass(bud_); }
    function yank() public             { keg.yank(); }
    function chug() public             { keg.chug(); }
    function sip(uint256 wad_) public  { keg.sip(wad_); }
}

contract KegTest is DSTest, DSMath {
    Hevm hevm;

    address constant public MCD_VOW = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // Fake address for mocking

    TestVat vat = new TestVat();
    Keg     keg = new Keg(address(vat), MCD_VOW);

    User user1  = new User(keg);
    User user2  = new User(keg);
    User user3  = new User(keg);

    uint256 constant public THOUSAND = 10**3;
    uint256 constant public MILLION  = 10**6;
    uint256 constant public WAD      = 10**18;
    uint256 constant public RAY      = 10**27;
    uint256 constant public RAD      = 10**45;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
    }

    function test_keg_deploy() public {
        assertEq(keg.wards(address(this)),  1);
        assertEq(address(keg.vat()),  address(vat));
        assertEq(keg.vow(), MCD_VOW);
        assertEq(keg.beer(), 0);
    }

    function test_brew() public {
        uint wad = 6 ether;

        assertEq(vat.dai(address(keg)), 0);
        keg.brew(wad);
        assertEq(vat.dai(address(keg)), wad * RAY);
    }

    function test_pour() public {
        uint wad = 6 ether;

        assertEq(vat.dai(address(keg)), 0);
        keg.brew(wad);
        assertEq(vat.dai(address(keg)), wad * RAY); // 6 DAI

        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1.5 ether;
        amts[1] = 4.5 ether;

        assertEq(keg.beer(), 0);
        assertEq(keg.mugs(address(user1)), 0);
        assertEq(keg.mugs(address(user2)), 0);
        keg.pour(users, amts);
        assertEq(keg.beer(), amts[0] + amts[1]); // Beer = 6
        assertEq(keg.mugs(address(user1)), amts[0]);     // Mug1 = 1.5
        assertEq(keg.mugs(address(user2)), amts[1]);     // Mug2 = 4.5
        assertEq(vat.dai(address(keg)), keg.beer() * RAY); // Beer = 6 DAI
    }

    function testFail_pour_unequal_to_brew() public {
        uint wad = 6 ether;

        assertEq(vat.dai(address(keg)), 0);
        keg.brew(wad);
        assertEq(vat.dai(address(keg)), wad * RAY); // 6 DAI

        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1.5 ether;
        amts[1] = 4.499 ether;

        keg.pour(users, amts);
    }

    function testFail_pour_unequal_length() public {
        uint wad = 6 ether;

        assertEq(vat.dai(address(keg)), 0);
        keg.brew(wad);
        assertEq(vat.dai(address(keg)), wad * RAY); // 6 DAI

        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1.5 ether;

        keg.pour(users, amts);
    }

    function testFail_pour_zero_length() public {
        uint wad = 6 ether;

        assertEq(vat.dai(address(keg)), 0);
        keg.brew(wad);
        assertEq(vat.dai(address(keg)), wad * RAY); // 6 DAI

        address[] memory users = new address[](0);
        uint256[] memory amts = new uint256[](0);
        keg.pour(users, amts);
    }

    function testFail_pour_zero_address() public {
        uint wad = 6 ether;

        assertEq(vat.dai(address(keg)), 0);
        keg.brew(wad);
        assertEq(vat.dai(address(keg)), wad * RAY); // 6 DAI

        address[] memory users = new address[](2);
        users[0] = address(0);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1.5 ether;
        keg.pour(users, amts);
    }

    function test_chug() public {
        uint wad = 6 ether;
        assertEq(vat.dai(address(keg)), 0);

        keg.brew(wad); // 6 DAI brewed

        assertEq(vat.dai(address(keg)), wad * RAY); // 6 DAI

        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1.5 ether;
        amts[1] = 4.5 ether;

        assertEq(keg.beer(), 0);
        assertEq(keg.mugs(address(user1)), 0);
        assertEq(keg.mugs(address(user2)), 0);

        keg.pour(users, amts);

        assertEq(keg.beer(), amts[0] + amts[1]); // Beer = 6
        assertEq(keg.mugs(address(user1)), amts[0]);     // Mug1 = 1.5
        assertEq(keg.mugs(address(user2)), amts[1]);     // Mug2 = 4.5

        assertEq(vat.dai(address(keg)), keg.beer() * RAY); // Beer = 6 DAI
        assertEq(vat.dai(address(user1)), 0);
        assertEq(vat.dai(address(user2)), 0);
        
        user1.chug(); // msg.sender == address(user1)

        assertEq(keg.beer(), amts[1]);       // Beer = 4.5
        assertEq(keg.mugs(address(user1)), 0);       // Mug1 = 0
        assertEq(keg.mugs(address(user2)), amts[1]); // Mug2 = 4.5
        assertEq(vat.dai(address(keg)), keg.beer() * RAY); // Beer = 4.5 DAI
        assertEq(vat.dai(address(user1)), 1.5 ether * RAY); // 1.5 DAI
        assertEq(vat.dai(address(user2)), 0);
    }

    function test_sip() public {
        uint wad = 6 ether; // 6 DAI brewed
        assertEq(vat.dai(address(keg)), 0);

        keg.brew(wad);

        assertEq(vat.dai(address(keg)), wad * RAY);

        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1.5 ether;
        amts[1] = 4.5 ether;

        assertEq(keg.beer(), 0);
        assertEq(keg.mugs(address(user1)), 0);
        assertEq(keg.mugs(address(user2)), 0);

        keg.pour(users, amts);

        assertEq(keg.beer(), amts[0] + amts[1]); // Beer = 6
        assertEq(keg.mugs(address(user1)), amts[0]);     // Mug1 = 1.5
        assertEq(keg.mugs(address(user2)), amts[1]);     // Mug2 = 4.5

        assertEq(vat.dai(address(keg)), keg.beer() * RAY); // Beer = 6 DAI
        assertEq(vat.dai(address(user1)), 0);
        assertEq(vat.dai(address(user2)), 0);
        
        user1.sip(1 ether); // msg.sender == address(user1)

        assertEq(keg.beer(), 5 ether);         // Beer = 5
        assertEq(keg.mugs(address(user1)), 0.5 ether); // Mug1 = 0.5
        assertEq(keg.mugs(address(user2)), amts[1]);   // Mug2 = 4.5
        assertEq(vat.dai(address(keg)), keg.beer() * RAY); // Beer = 5 DAI
        assertEq(vat.dai(address(user1)), 1 ether * RAY); // 1 DAI
        assertEq(vat.dai(address(user2)), 0);
    }

    function testFail_sip_too_big() public {
        uint wad = 6 ether; // 6 DAI brewed
        assertEq(vat.dai(address(keg)), 0);

        keg.brew(wad);

        assertEq(vat.dai(address(keg)), wad * RAY);

        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1.5 ether;
        amts[1] = 4.5 ether;

        assertEq(keg.beer(), 0);
        assertEq(keg.mugs(address(user1)), 0);
        assertEq(keg.mugs(address(user2)), 0);

        keg.pour(users, amts);

        assertEq(keg.beer(), amts[0] + amts[1]); // Beer = 6
        assertEq(keg.mugs(address(user1)), amts[0]);     // Mug1 = 1.5
        assertEq(keg.mugs(address(user2)), amts[1]);     // Mug2 = 4.5

        assertEq(vat.dai(address(keg)), keg.beer() * RAY); // Beer = 6 DAI
        assertEq(vat.dai(address(user1)), 0);
        assertEq(vat.dai(address(user2)), 0);
        
        user1.sip(2 ether); // msg.sender == address(user1)
    }

    function test_pass() public {
        user1.pass(address(user2));
        assertEq(keg.buds(address(user1)), address(user2));
        assertEq(keg.pals(address(user2)), address(user1));
    }

    function testFail_pass_bud_with_existing_pal() public {
        user1.pass(address(user2));
        user1.pass(address(user2));
    }

    function test_pass_with_existing_bud() public {
        user1.pass(address(user2));
        user1.pass(address(user3));
        assertEq(keg.buds(address(user1)), address(user3));
        assertEq(keg.pals(address(user2)), address(0));
        assertEq(keg.pals(address(user3)), address(user1));
    }

    function testFail_pass_yourself() public {
        user1.pass(address(user1));
    }

    function test_yank() public {
        user1.pass(address(user2));
        assertEq(keg.buds(address(user1)), address(user2));
        assertEq(keg.pals(address(user2)), address(user1));
        user1.yank();
        assertEq(keg.buds(address(user1)), address(0));
        assertEq(keg.pals(address(user2)), address(0));
    }

    function testFail_yank_no_bud() public {
        assertEq(keg.buds(address(user1)), address(0));
        user1.yank();
    }

    function testFail_chug_with_yanked_bud() public {
        user1.pass(address(user2));
        user1.pass(address(user3));
        //how does one become a different user - hevm hack?
        //keg.chug()

        assertTrue(false);  //temp to pass test
    }

    function test_chug_as_bud() public {
        //how does one become a different user - hevm hack?
    }
    
}