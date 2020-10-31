// Keg.sol

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
    function hope(address usr) external;
    function nope(address usr) external;
    function suck(address, address, uint256) external;
    function move(address, address, uint256) external;
    function dai(address) external view returns (uint256);
}

contract KegLike {
    function pour(bytes32 flight, uint256 rad) external;
}

interface FlapLike {
    function kick(uint256 lot, uint256 bid) external returns (uint256);
    function cage(uint256) external;
}

// A tap can suck funds from the vow to fill the keg at a preset rate.
contract Tap is LibNote {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Tap/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external note auth { stopped = 1; }
    function start() external note auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Tap/is-stopped"); _; }

    VatLike public vat;
    address public vow;
    KegLike public keg;

    bytes32 public flight;  // The target flight in keg
    uint256 public rate;    // The per-second rate of distributing funds [rad]
    uint256 public rho;     // Time of last pump [unix epoch time]

    uint256 constant RAY = 10 ** 27;

    constructor(address vat_, address vow_, address keg_, bytes32 flight_, uint256 rate_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        vow = vow_;
        keg = KegLike(keg_);
        vat.hope(keg_);
        flight = flight_;
        rate = rate_;
        rho = now;
    }

    // --- Math ---
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        if (what == "vat") vat = VatLike(addr);
        else if (what == "vow") vow = addr;
        else if (what == "keg") {
            vat.nope(address(keg));
            keg = KegLike(addr);
            vat.hope(addr);
        } else revert("Tap/file-unrecognized-param");
    }
    function file(bytes32 what, bytes32 data) external note auth {
        require(now == rho, "Tap/rho-not-updated");
        if (what == "flight") flight = data;
        else revert("Tap/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external note auth {
        require(now == rho, "Tap/rho-not-updated");
        if (what == "rate") rate = data;
        else revert("Tap/file-unrecognized-param");
    }

    function pump() external note stoppable {
        require(now >= rho, "Tap/invalid-now");
        uint256 rad = mul(now - rho, rate);
        if (rad > 0) {
            vat.suck(address(vow), address(this), rad);
            keg.pour(flight, rad);
        }
        rho = now;
    }
}

// A modified version of Tap which sits between the vow and the actual flapper.
// Redirects funds to the keg at a preset fractional flow.
contract FlapTap is LibNote, FlapLike {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "FlapTap/not-authorized");
        _;
    }

    VatLike public vat;
    FlapLike public flapper;
    KegLike public keg;
    uint256  public live;   // Active Flag

    bytes32 public flight;  // The target flight in keg
    uint256 public flow;    // The fraction of the lot which goes to the keg [wad]

    uint256 constant WAD = 10 ** 18;

    constructor(address vat_, address flapper_, address keg_, bytes32 flight_, uint256 flow_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        flapper = FlapLike(flapper_);
        keg = KegLike(keg_);
        vat.hope(flapper_);
        vat.hope(keg_);
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
    function file(bytes32 what, address addr) external note auth {
        if (what == "vat") vat = VatLike(addr);
        else if (what == "vow") {
            vat.nope(address(flapper));
            flapper = FlapLike(addr);
            vat.hope(addr);
        } else if (what == "keg") {
            vat.nope(address(keg));
            keg = KegLike(addr);
            vat.hope(addr);
        } else revert("FlapTap/file-unrecognized-param");
    }
    function file(bytes32 what, bytes32 data) external note auth {
        if (what == "flight") flight = data;
        else revert("FlapTap/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external note auth {
        if (what == "flow") require((flow = data) <= WAD, "FlapTap/invalid-flow");
        else revert("FlapTap/file-unrecognized-param");
    }

    function kick(uint256 lot, uint256 bid) external note auth returns (uint256) {
        require(live == 1, "FlapTap/not-live");
        uint256 beer = mul(lot, flow) / WAD;
        vat.move(msg.sender, address(this), lot);
        keg.pour(flight, beer);
        return flapper.kick(sub(lot, beer), bid);
    }

    function cage(uint256) external note auth {
        require(live == 1, "FlapTap/not-live");
        uint256 rad = vat.dai(address(flapper));
        flapper.cage(rad);
        vat.move(address(this), msg.sender, rad);
        live = 0;
    }
}

// Keg controls payouts
contract Keg is LibNote {

    struct Pint {
        address bum;  // Who to pay
        uint256 share; // The fraction of the total amount to pay out [wad]
    }

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; emit NewBrewMaster(usr); }
    function deny(address usr) external note auth { wards[usr] = 0; emit RetiredBrewMaster(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "Keg/not-authorized");
        _;
    }

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        if (what == "vat") vat = VatLike(addr);
        else revert("Keg/file-unrecognized-param");
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external note auth { stopped = 1; }
    function start() external note auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    uint256 constant WAD = 10 ** 18;

    VatLike public vat;

    // Define payout ratios
    mapping (bytes32 => Pint[]) public flights;       // The Pint definitions

    // --- Events ---
    event NewBrewMaster(address brewmaster);
    event RetiredBrewMaster(address brewmaster);
    event PourBeer(address bartender, uint256 beer);
    event OrdersUp(bytes32 flight);
    event OrderRevoked(bytes32 flight);

    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
    }

    // Credits people with rights to withdraw funds from the pool
    function pour(address[] calldata bums, uint256[] calldata rad) external note stoppable {
        require(bums.length == rad.length, "Keg/unequal-payees-and-amounts");
        require(bums.length > 0, "Keg/no-bums");
        for (uint256 i = 0; i < rad.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            vat.move(msg.sender, bums[i], rad[i]);
            emit PourBeer(bums[i], rad[i]);
        }
    }

    // Credits people with rights to withdraw funds from the pool using a preset flight
    function pour(bytes32 flight, uint256 rad) external note stoppable {
        Pint[] memory pints = flights[flight];

        require(rad > 0, "Keg/rad-zero");
        require(pints.length > 0, "Keg/flight-not-set");       // numPints will be empty when not set
        
        uint256 suds = 0;
        for (uint256 i = 0; i < pints.length; i++) {
            Pint memory pint = pints[i];
            uint256 sud;
            if (i != pints.length - 1) {
                // Otherwise use the share amount
                sud = mul(rad, pints[i].share) / WAD;
            } else {
                // Add whatevers left over to the last mug to account for rounding errors
                sud = sub(rad, suds);
            }
            suds = add(suds, sud);
            vat.move(msg.sender, pint.bum, sud);
            emit PourBeer(pint.bum, sud);
        }
    }

    // Pre-authorize a flight distribution of funds
    function seat(bytes32 flight, address[] calldata bums, uint256[] calldata shares) external note auth {
        require(bums.length == shares.length, "Keg/unequal-bums-and-shares");
        require(bums.length > 0, "Keg/zero-bums");

        // Pint shares need to add up to 100%
        uint256 total = 0;
        for (uint256 i = 0; i < bums.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            total = add(total, shares[i]);
            flights[flight].push(Pint(bums[i], shares[i]));
        }
        require(total == WAD, "Keg/invalid-flight");
        emit OrdersUp(flight);
    }

    // Deauthorize a flight
    function revoke(bytes32 flight) external note auth {
        require(flights[flight].length > 0, "Keg/flight-not-set");       // pints will be 0 when not set
        for (uint256 i = 0; i < flights[flight].length; i++) {
            delete flights[flight][i];
        }
        emit OrderRevoked(flight);
    }

}