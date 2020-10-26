// Tap.sol

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

pragma solidity >=0.5.15;

contract LibNote {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    modifier note {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: selector, caller, arg1 and arg2
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 caller,                              // msg.sender
                 calldataload(4),                     // arg1
                 calldataload(36)                     // arg2
                )
        }
    }
}

contract VatLike {
	function suck(address, address, uint256) external;
    function move(address, address, uint256) external;
    function dai(address) external view returns (uint256);
}

contract DaiLike {
	function approve(address, uint256) external;
}

contract DaiJoinLike {
	function dai() external view returns (address);
	function exit(address, uint256) external;
}

contract KegLike {
	function pour(bytes32 flight, uint256 wad) external;
}

interface FlapLike {
    function kick(uint256 lot, uint256 bid) external returns (uint256);
    function cage(uint256) external;
}

// A modified version of Tap which sits between the vow and the actual flapper.
// Redirects funds to the keg at a preset fractional flow.
contract FlapTap is LibNote, FlapLike {

	// --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Keg/not-authorized");
        _;
    }

    VatLike public vat;
    FlapLike public flapper;
    DaiJoinLike public daiJoin;
    KegLike public keg;
    uint256  public live;   // Active Flag

    bytes32 public flight;  // The target flight in keg
    uint256 public flow;    // The fraction of the lot which goes to the keg [wad]

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    constructor(address vat_, address flapper_, address daiJoin_, address keg_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        flapper = FlapLike(flapper_);
        daiJoin = DaiJoinLike(daiJoin_);
        live = 1;
    }

    // --- Math ---
    function sub(uint256 x, uint256 y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function kick(uint256 lot, uint256 bid) external note auth returns (uint256) {
        require(live == 1, "FlapTap/not-live");
        uint256 beer = mul(lot, flow) / RAD;
    	vat.move(msg.sender, address(this), lot);
        daiJoin.exit(address(this), beer);
        DaiLike(daiJoin.dai()).approve(address(keg), beer);
        keg.pour(flight, beer);
        return flapper.kick(sub(lot, beer * RAY), bid);
    }

    function cage(uint256 rad) external note auth {
        require(live == 1, "FlapTap/not-live");
        flapper.cage(rad);
        vat.move(address(this), msg.sender, rad);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
    	if (what == "vat") vat = VatLike(addr);
    	else if (what == "vow") flapper = FlapLike(addr);
    	else if (what == "keg") keg = KegLike(addr);
    	else revert("FlapTap/file-unrecognized-param");
    }
    function file(bytes32 what, bytes32 data) external note auth {
    	if (what == "flight") flight = data;
    	else revert("FlapTap/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external note auth {
    	if (what == "flow") require((flow = data) <= WAD, "FlapTap/invalid-flow");
    	else revert("FlapTap/file-unrecognized-param");
    }

}