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

interface IERC20 {
    function transfer(address,uint256) external returns (bool);
    function transferFrom(address,address,uint256) external returns (bool);
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
    DaiJoinLike public daiJoin;
    KegLike public keg;

    bytes32 public flight;  // The target flight in keg
    uint256 public rate;    // The per-second rate of distributing funds [wad]
    uint256 public rho;     // Time of last pump [unix epoch time]

    uint256 constant RAY = 10 ** 27;

    constructor(address vat_, address vow_, address daiJoin_, address keg_, bytes32 flight_, uint256 rate_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        vow = vow_;
        daiJoin = DaiJoinLike(daiJoin_);
        keg = KegLike(keg_);
        flight = flight_;
        rate = rate_;
        rho = now;
    }

    // --- Math ---
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function pump() external note stoppable {
        require(now >= rho, "Tap/invalid-now");
        uint256 wad = mul(now - rho, rate);
        if (wad > 0) {
            vat.suck(address(vow), address(this), wad * RAY);
            daiJoin.exit(address(this), wad);
            DaiLike(daiJoin.dai()).approve(address(keg), wad);
            keg.pour(flight, wad);
        }
        rho = now;
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
    	if (what == "vat") vat = VatLike(addr);
    	else if (what == "vow") vow = addr;
    	else if (what == "keg") keg = KegLike(addr);
    	else revert("Tap/file-unrecognized-param");
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
    DaiJoinLike public daiJoin;
    KegLike public keg;
    uint256  public live;   // Active Flag

    bytes32 public flight;  // The target flight in keg
    uint256 public flow;    // The fraction of the lot which goes to the keg [wad]

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    constructor(address vat_, address flapper_, address daiJoin_, address keg_, bytes32 flight_, uint256 flow_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        flapper = FlapLike(flapper_);
        daiJoin = DaiJoinLike(daiJoin_);
        keg = KegLike(keg_);
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

// Keg controls payouts
contract Keg is LibNote {

    struct Pint {
        address mug;   // Who to pay
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

    // --- Stop ---
    uint256 public stopped;
    function stop() external note auth { stopped = 1; }
    function start() external note auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    IERC20 public token;

    uint256 public beer; // Total encumbered funds (Available for people to withdraw)

    uint256 constant WAD = 10 ** 18;

    // Accounting for tracking users availale balances
    mapping (address => uint256) public mugs;

    // Two-way mapping tracks delegates
    mapping (address => address) public pals;   // Delegate -> Original
    mapping (address => address) public buds;   // Original -> Delegate

    // Define payout ratios
    mapping (bytes32 => uint256) public pints;                          // Number of pints
    mapping (bytes32 => mapping(uint256 => Pint)) public flights;       // The Pint definitions

    // --- Events ---
    event NewBrewMaster(address brewmaster);
    event RetiredBrewMaster(address brewmaster);
    event BrewBeer(uint256 beer);
    event PourBeer(address bartender, uint256 beer);
    event HoldMyBeerBro(address indexed owner, address bud);
    event ByeFelicia(address indexed owner, address bud);
    event JustASip(address bum, uint256 beer);
    event DownTheHatch(address bum, uint256 beer);
    event OrdersUp(bytes32 flight);
    event OrderRevoked(bytes32 flight);

    constructor(address token_) public {
        wards[msg.sender] = 1;
        token = IERC20(token_);
        beer = 0;
    }

    // Credits people with rights to withdraw funds from the pool
    function pour(address[] calldata bums, uint256[] calldata wad) external note stoppable {
        require(bums.length == wad.length, "Keg/unequal-payees-and-amounts");
        require(bums.length > 0, "Keg/no-bums");
        uint256 suds = 0;
        for (uint256 i = 0; i < wad.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            mugs[bums[i]] = add(mugs[bums[i]], wad[i]);
            suds          = add(suds, wad[i]);
            emit PourBeer(bums[i], wad[i]);
        }
        require(token.transferFrom(msg.sender, address(this), suds), "Keg/insufficient-tokens");
        beer = add(beer, suds);
    }

    // Credits people with rights to withdraw funds from the pool using a preset flight
    function pour(bytes32 flight, uint256 wad) external note stoppable {
        require(wad > 0, "Keg/wad-zero");
        uint256 npints = pints[flight];
        require(npints > 0, "Keg/flight-not-set");       // numPints will be empty when not set
        
        uint256 suds = 0;
        for (uint256 i = 0; i < npints; i++) {
            Pint memory pint = flights[flight][i];
            uint256 sud;
            if (i == npints - 1) {
                // Add whatevers left over to the last mug to account for rounding errors
                sud = sub(wad, suds);
            } else {
                // Otherwise use the share amount
                sud = mul(wad, flights[flight][i].share) / WAD;
            }
            mugs[pint.mug] = add(mugs[pint.mug], sud);
            suds = add(suds, sud);
            emit PourBeer(pint.mug, sud);
        }
        require(token.transferFrom(msg.sender, address(this), suds), "Keg/insufficient-tokens");
        beer = add(beer, suds);
    }

    // User delegates compensation to another address
    function pass(address bud) external {
        require(bud != msg.sender, "Keg/cannot_delegate_to_self");
        require(pals[bud] == address(0), "Keg/bud-already-has-a-pal");
        // Remove existing delegate
        if (buds[msg.sender] != address(0)) yank();
        // Original addr -> delegated addr
        buds[msg.sender] = bud;
        // Delegated addr -> original addr
        pals[bud] = msg.sender;
        emit HoldMyBeerBro(msg.sender, bud);
    }

    // User revokes delegation
    function yank() public {
        require(buds[msg.sender] != address(0), "Keg/no-bud");
        pals[buds[msg.sender]] = address(0);
        buds[msg.sender] = address(0);
        emit ByeFelicia(msg.sender, buds[msg.sender]);
    }

    // User withdraws all funds
    function chug() external {
        uint256 pint = mugs[msg.sender] + mugs[pals[msg.sender]];
        require(pint != uint256(0), "Keg/too-thirsty-not-enough-beer");
        beer = sub(beer, pint);
        mugs[msg.sender] = 0;
        mugs[pals[msg.sender]] = 0;

        token.transfer(msg.sender, pint);
        emit DownTheHatch(msg.sender, pint);
    }

    // User withdraws some of their compensation
    // TODO: Handle case where: mugs[pals[msg.sender]] < wad < (mugs[pals[msg.sender]] + mugs[bum])
    // TODO: Handle case where: mugs[pals[msg.sender]] == 0 && mugs[msg.sender] > 0
    function sip(uint256 wad) external {
        // Whose tab are we drinking on
        address bum = pals[msg.sender] != address(0) ? pals[msg.sender] : msg.sender;
        mugs[bum] = sub(mugs[bum], wad);
        beer = sub(beer, wad);

        token.transfer(msg.sender, wad);
        emit JustASip(msg.sender, wad);
    }

    // Pre-authorize a flight distribution of funds
    function serve(bytes32 flight, address[] calldata bums, uint256[] calldata shares) external note auth {
        require(bums.length == shares.length, "Keg/unequal-bums-and-shares");
        require(bums.length > 0, "Keg/zero-bums");

        // Pints need to add up to 100%
        pints[flight] = bums.length;
        uint256 total = 0;
        for (uint256 i = 0; i < bums.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            total = add(total, shares[i]);
            flights[flight][i] = Pint(bums[i], shares[i]);
        }
        require(total == WAD, "Keg/invalid-flight");
        emit OrdersUp(flight);
    }

    // Deauthorize a flight
    function revoke(bytes32 flight) external note auth {
        require(pints[flight] > 0, "Keg/flight-not-set");       // pints will be 0 when not set
        uint256 npints = pints[flight];
        for (uint256 i = 0; i < npints; i++) {
            delete flights[flight][i];
        }
        delete pints[flight];
        emit OrderRevoked(flight);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
    	if (what == "token") token = IERC20(addr);
    	else revert("Keg/file-unrecognized-param");
    }
}