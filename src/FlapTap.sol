// FlapTap.sol

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

import "dss-interfaces/dss/FlapAbstract.sol";
import "dss-interfaces/dss/VatAbstract.sol";
import "./KegAbstract.sol";

// A modified version of Tap which sits between the vow and the actual flapper.
// Redirects funds to the keg at a preset fractional flow.
contract FlapTap {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "FlapTap/not-authorized");
        _;
    }

    VatAbstract public immutable vat;
    FlapAbstract public immutable flapper;
    KegAbstract public immutable keg;

    uint256  public live;   // Active Flag
    string public flight;   // The target flight in keg
    uint256 public flow;    // The fraction of the lot which goes to the keg [wad]

    uint256 constant WAD = 10 ** 18;

    constructor(address keg_, address flapper_, string memory flight_, uint256 flow_) public {
        wards[msg.sender] = 1;
        KegAbstract keg__ = keg = KegAbstract(keg_);
        VatAbstract vat__ = vat = VatAbstract(keg__.vat());
        flapper = FlapAbstract(flapper_);
        vat__.hope(flapper_);
        vat__.hope(keg_);
        flight = flight_;
        require((flow = flow_) <= WAD, "FlapTap/invalid-flow");
        live = 1;
    }

    // --- Math ---
    function sub(uint256 x, uint256 y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, string calldata data) external auth {
        if (what == "flight") flight = data;
        else revert("FlapTap/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external auth {
        if (what == "flow") require((flow = data) <= WAD, "FlapTap/invalid-flow");
        else revert("FlapTap/file-unrecognized-param");
    }

    function kick(uint256 lot, uint256 bid) external auth returns (uint256) {
        require(live == 1, "FlapTap/not-live");
        uint256 beer = mul(lot, flow) / WAD;
        vat.move(msg.sender, address(this), lot);
        keg.pour(flight, beer);
        return flapper.kick(sub(lot, beer), bid);
    }

    function cage(uint256) external auth {
        require(live == 1, "FlapTap/not-live");
        uint256 rad = vat.dai(address(flapper));
        flapper.cage(rad);
        vat.move(address(this), msg.sender, rad);
        live = 0;
    }
}