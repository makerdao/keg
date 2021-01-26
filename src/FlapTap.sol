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

import "dss-interfaces/dss/DaiAbstract.sol";
import "dss-interfaces/dss/DaiJoinAbstract.sol";
import "dss-interfaces/dss/FlapAbstract.sol";
import "dss-interfaces/dss/VatAbstract.sol";
import "./KegAbstract.sol";

// A modified version of Tap which sits between the vow and the actual flapper.
// Redirects funds to the keg at a preset fractional flow.
contract FlapTap {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "FlapTap/not-authorized");
        _;
    }

    // --- Variable ---
    VatAbstract     public immutable vat;
    FlapAbstract    public immutable flapper;
    KegAbstract     public immutable keg;
    DaiJoinAbstract public immutable daiJoin;

    uint256 public live;    // Active Flag
    bytes32 public flight;  // The target flight in keg
    uint256 public flow;    // The fraction of the lot which goes to the keg [wad]

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 data);
    event File(bytes32 indexed what, uint256 data);

    // --- Init ---
    constructor(KegAbstract keg_, DaiJoinAbstract daiJoin_, address flapper_, bytes32 flight_, uint256 flow_) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        keg     = keg_;
        daiJoin = daiJoin_;
        flapper = FlapAbstract(flapper_);
        flight  = flight_;
        flow    = flow_;
        live    = 1;

        VatAbstract vat_ = vat = VatAbstract(daiJoin_.vat());
        DaiAbstract dai  = DaiAbstract(daiJoin_.dai());

        require(flow_ <= WAD, "FlapTap/invalid-flow");

        vat_.hope(flapper_);
        vat_.hope(address(daiJoin_));

        require(dai.approve(address(keg_), uint256(-1)), "FlapTap/dai-approval-failure");
    }

    // --- Math ---
    function sub(uint256 x, uint256 y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, bytes32 data) external auth {
        if (what == "flight") flight = data;
        else revert("FlapTap/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "flow") {
            require(data <= WAD, "FlapTap/invalid-flow");
            flow = data;
        } else revert("FlapTap/file-unrecognized-param");

        emit File(what, data);
    }

    function kick(uint256 lot, uint256 bid) external auth returns (uint256) {
        require(live == 1, "FlapTap/not-live");
        uint256 wad = mul(lot, flow) / RAD;
        uint256 rad = mul(wad, RAY);
        vat.move(msg.sender, address(this), lot);
        daiJoin.exit(address(this), wad);
        keg.pour(flight, wad);
        return flapper.kick(sub(lot, rad), bid);
    }

    function cage(uint256) external auth {
        require(live == 1, "FlapTap/not-live");
        uint256 rad = vat.dai(address(flapper));
        flapper.cage(rad);
        vat.move(address(this), msg.sender, rad);
        live = 0;
    }
}