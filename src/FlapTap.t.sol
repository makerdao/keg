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

pragma solidity ^0.6.7;

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

contract Wallet {
    constructor() public {}
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

    Wallet wallet1;
    Wallet wallet2;
    Wallet wallet3;

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

        keg = KegAbstract(address(new Keg(address(dai))));
        dai.approve(address(keg), uint256(-1));
        vat.hope(address(keg));
        flapTap = new FlapTap(keg, daiJoin, address(flapper), "flap",  0.5 ether);
        flapTap.rely(address(vow));

        wallet1 = new Wallet();
        wallet2 = new Wallet();
        wallet3 = new Wallet();
    }


    // file("flight")
    function test_flight() public {
        assertEq(flapTap.flight(), "flap");

        flapTap.file("flight", "opt");

        assertEq(flapTap.flight(), "opt");
    }

    function testFail_flight() public {
        tap.deny(me);
        tap.file("flight", "opt");
    }

    // file("flow")
    function test_flow() public {
        assertEq(flapTap.flow(), 5 * WAD / 10);
        flapTap.file("flow", 100000);

        assertEq(flapTap.flow(), 100000);
    }

    function testFail_flow() public {
        flapTap.deny(me);
        flapTap.file("flow", uint256(0));
    }

    function testFail_flow_over_wad() public {
        flapTap.file("flow", WAD + 1000);
    }

}