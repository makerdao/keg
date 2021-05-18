// SPDX-License-Identifier: AGPL-3.0-or-later
// Keg.t.sol

// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "lib/dss-interfaces/src/Interfaces.sol";
import {DaiJoin} from "dss/join.sol";
import {Dai} from "dss/dai.sol";

import "./Keg.sol";
import "./Tap.sol";
import "./FlapTap.sol";

interface Hevm { function warp(uint) external; }

contract TestVat is DSMath {

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) public auth { wards[usr] = 1; }
    function deny(address usr) public auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Vat/not-authorized");
        _;
    }

    mapping(address => mapping (address => uint)) public can;
    function hope(address usr) public { can[msg.sender][usr] = 1; }
    function nope(address usr) public { can[msg.sender][usr] = 0; }
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    mapping (address => uint256) public dai;

    constructor() public {
        wards[msg.sender] = 1;
    }

    function mint(address usr, uint rad) public {
        dai[usr] = add(dai[usr], rad);
    }

    function suck(address u, address v, uint rad) auth public {
        u;
        mint(v, rad);
    }

    function move(address src, address dst, uint256 rad) public {
        require(wish(src, msg.sender), "Vat/not-allowed");
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }

}

contract TestFlapper is DSMath {

    VatAbstract public vat;
    uint256 public kicks = 0;
    uint256 public amountAuctioned = 0;

    constructor(address vat_) public {
        vat = VatAbstract(vat_);
    }

    function kick(uint256 lot, uint256 bid) public returns (uint256 id) {
        bid;
        id = ++kicks;
        amountAuctioned += lot;
        vat.move(msg.sender, address(this), lot);
    }

    function cage(uint256 rad) public {
        vat.move(address(this), msg.sender, rad);
    }

}

contract TestVow is DSMath {

    TestVat public vat;
    FlapAbstract public flapper;
    uint256 public lastId;
    uint256 public bump = 10000 * 1e45;

    constructor(address vat_, address flapper_) public {
        vat = TestVat(vat_);
        flapper = FlapAbstract(flapper_);
        vat.hope(flapper_);
        lastId = 0;
    }

    function flap() public returns (uint id) {
        vat.mint(address(this), bump);
        id = flapper.kick(bump, 0);
        require(id == lastId + 1, "failed to increment id");
        lastId = id;
    }

    function cage() public {
        flapper.cage(vat.dai(address(flapper)));
    }

    function file(bytes32 what, address data) public {
        if (what == "flapper") {
            vat.nope(address(flapper));
            flapper = FlapAbstract(data);
            vat.hope(data);
        }
        else revert("Vow/file-unrecognized-param");
    }

}

contract User {
    KegAbstract public keg;
    constructor(KegAbstract keg_) public { keg = keg_; }
}

contract KegTest is DSTest, DSMath {
    Hevm hevm;

    address constant public MCD_VOW = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // Fake address for mocking

    address me;
    TestVat vat;
    KegAbstract keg;
    Tap tap;
    FlapTap flapTap;
    TestFlapper flapper;
    TestVow vow;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;

    User user1;
    User user2;
    User user3;

    uint256 constant public THOUSAND = 10**3;
    uint256 constant public MILLION  = 10**6;
    uint256 constant public RAD      = 10**45;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function assertEq(uint256 a, uint256 b, uint256 tolerance) internal {
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > a * tolerance / WAD) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            fail();
        }
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new TestVat();
        flapper = new TestFlapper(address(vat));
        vow = new TestVow(address(vat), address(flapper));

        dai = DaiAbstract(address(new Dai(0)));
        daiJoin = DaiJoinAbstract(address(new DaiJoin(address(vat), address(dai))));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        keg = KegAbstract(address(new Keg()));
        dai.approve(address(keg), uint256(-1));
        vat.hope(address(keg));
        tap = new Tap(keg, daiJoin, address(vow), "operations", WAD / (1 days));
        vat.rely(address(tap));
        flapTap = new FlapTap(keg, daiJoin, address(flapper), "flap", 0.5 ether);
        flapTap.rely(address(vow));

        user1 = new User(keg);
        user2 = new User(keg);
        user3 = new User(keg);
    }

    function test_keg_deploy() public {
        assertEq(keg.wards(me),  1);
    }

    function test_seat() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether;   // 25% split
        amts[1] = 0.75 ether;   // 75% split
        bytes32 flight = "flight1";

        keg.seat(flight, address(dai), users, amts);
        assertEq(keg.gems(flight), address(dai));
        Pint[] memory pints = keg.pints(flight);
        assertEq(pints[0].bum, address(user1));
        assertEq(pints[0].share, 0.25 ether);
        assertEq(pints[1].bum, address(user2));
        assertEq(pints[1].share, 0.75 ether);
        assertTrue(keg.exists(flight));
    }

    function test_revoke() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether;   // 25% split
        amts[1] = 0.75 ether;   // 75% split
        bytes32 flight = "flight1";

        keg.seat(flight, address(dai), users, amts);
        assertEq(keg.gems(flight), address(dai));
        Pint[] memory pints = keg.pints(flight);
        assertEq(pints[0].bum, address(user1));
        assertEq(pints[0].share, 0.25 ether);
        assertEq(pints[1].bum, address(user2));
        assertEq(pints[1].share, 0.75 ether);
        assertTrue(keg.exists(flight));

        keg.revoke(flight);

        assertEq(keg.gems(flight), address(0));
        assertTrue(!keg.exists(flight));
    }

    function testFail_seat_bad_shares() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether + 1;   // 25% split + 1 wei
        amts[1] = 0.75 ether;       // 75% split
        keg.seat("flight1", address(dai), users, amts);
    }

    function testFail_seat_unequal_length() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1 ether;

        keg.seat("flight1", address(dai), users, amts);
    }

    function testFail_seat_zero_length() public {
        address[] memory users = new address[](0);
        uint256[] memory amts = new uint256[](0);
        keg.seat("flight1", address(dai), users, amts);
    }

    function testFail_seat_zero_address() public {
        address[] memory users = new address[](2);
        users[0] = address(0);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1 ether;
        keg.seat("flight1", address(dai), users, amts);
    }

    function test_pour_flight() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.3 ether;   // 30% split
        amts[1] = 0.7 ether;   // 70% split
        bytes32 flight = "flight1";

        keg.seat(flight, address(dai), users, amts);
        dai.mint(me, 100 * WAD);

        keg.pour(flight, 10 * WAD);
        assertEq(dai.balanceOf(me), 90 * WAD);
        assertEq(dai.balanceOf(address(user1)), 3 * WAD);
        assertEq(dai.balanceOf(address(user2)), 7 * WAD);
    }

    function testFail_pour_flight_invalid() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether;   // 25% split
        amts[1] = 0.75 ether;   // 75% split
        bytes32 flight = "flight1";

        dai.mint(me, 100 * WAD);
        keg.pour(flight, 10 * WAD);
    }

    function test_pour_flight_zero() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether;   // 25% split
        amts[1] = 0.75 ether;   // 75% split
        bytes32 flight = "flight1";

        keg.seat(flight, address(dai), users, amts);
        dai.mint(me, 100 * WAD);
        keg.pour(flight, 0);
    }

    function test_pour_flight_one_wei() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether;   // 25% split
        amts[1] = 0.75 ether;   // 75% split
        bytes32 flight = "flight1";

        keg.seat(flight, address(dai), users, amts);
        dai.mint(me, 100 * WAD);
        keg.pour(flight, 1);

        // Rules are to give any fractional remainder to the last mug
        assertEq(dai.balanceOf(address(user1)), 0);
        assertEq(dai.balanceOf(address(user2)), 1);
        assertEq(dai.balanceOf(me), 100 * WAD - 1);
    }

    function testFail_pour_flight_not_enough_dai() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.25 ether;   // 25% split
        amts[1] = 0.75 ether;   // 75% split
        bytes32 flight = "flight1";

        keg.seat(flight, address(dai), users, amts);
        dai.mint(me, 1 * WAD);
        keg.pour(flight, 10 * WAD);
    }

    function test_tap_pump() public {
        address[] memory users = new address[](3);
        users[0] = address(user1);
        users[1] = address(user2);
        users[2] = address(user3);
        uint256[] memory amts = new uint256[](3);
        amts[0] = 0.65 ether;   // 65% split
        amts[1] = 0.25 ether;   // 25% split
        amts[2] = 0.10 ether;   // 10% split
        keg.seat(tap.flight(), address(dai), users, amts);

        uint256 rate = tap.rate();
        uint256 wad = rate * 1 days;        // Due to rounding errors this may not be exactly 1 rad
        hevm.warp(1 days);
        assertEq(now - tap.rho(), 1 days);
        tap.pump();
        assertEq(dai.balanceOf(address(user1)), wad * 65 / 100, WAD / 1000);  // Account for rounding errors of 0.1%
        assertEq(dai.balanceOf(address(user2)), wad * 25 / 100, WAD / 1000);
        assertEq(dai.balanceOf(address(user3)), wad - ((wad * 65 / 100) + (wad * 25 / 100)), WAD / 1000);
    }

    function testFail_tap_rate_change_without_pump() public {
        address[] memory users = new address[](3);
        users[0] = address(user1);
        users[1] = address(user2);
        users[2] = address(user3);
        uint256[] memory amts = new uint256[](3);
        amts[0] = 0.65 ether;   // 65% split
        amts[1] = 0.25 ether;   // 25% split
        amts[2] = 0.10 ether;   // 10% split
        keg.seat(tap.flight(), address(dai), users, amts);
        hevm.warp(1 days + 1);
        tap.file("rate", uint256(2 ether) / 1 days);
    }

    function test_tap_rate_change_with_pump() public {
        address[] memory users = new address[](3);
        users[0] = address(user1);
        users[1] = address(user2);
        users[2] = address(user3);
        uint256[] memory amts = new uint256[](3);
        amts[0] = 0.65 ether;   // 65% split
        amts[1] = 0.25 ether;   // 25% split
        amts[2] = 0.10 ether;   // 10% split
        keg.seat(tap.flight(), address(dai), users, amts);
        hevm.warp(1 days + 1);
        tap.pump();
        tap.file("rate", uint256(2 ether) / 1 days);
    }

    function test_flap_tap_deploy() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.50 ether;   // 50% split
        amts[1] = 0.50 ether;   // 50% split
        keg.seat(flapTap.flight(), address(dai), users, amts);

        assertEq(flapper.kicks(), 0);
        assertEq(vow.flap(), 1);
        assertEq(flapper.kicks(), 1);
        uint256 auctioned = vow.bump();
        assertEq(flapper.amountAuctioned(), auctioned);
        assertEq(vat.dai(address(flapper)), auctioned);

        // Insert the TapFlap in between the vow and flapper
        vow.file("flapper", address(flapTap));

        assertEq(vow.flap(), 2);
        assertEq(flapper.kicks(), 2);
        uint256 wad = vow.bump() * flapTap.flow() / RAD;
        auctioned += vow.bump() - wad * RAY;
        assertEq(flapper.amountAuctioned(), auctioned);
        assertEq(vat.dai(address(flapper)), auctioned);
        assertEq(dai.balanceOf(address(user1)), wad / 2);
        assertEq(dai.balanceOf(address(user2)), wad / 2);
    }

    function testFail_flap_tap_invalid_flow() public {
        flapTap.file("flow", 1.1 ether);
    }

    function test_flap_tap_cage() public {
        address[] memory users = new address[](2);
        users[0] = address(user1);
        users[1] = address(user2);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.50 ether;   // 50% split
        amts[1] = 0.50 ether;   // 50% split
        keg.seat(flapTap.flight(), address(dai), users, amts);
        vow.file("flapper", address(flapTap));
        vow.flap();
        vow.cage();

        // All dai should be returned to the vow
        assertEq(vat.dai(address(vow)), vow.bump() / 2);
    }

}
