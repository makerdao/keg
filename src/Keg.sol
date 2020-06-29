pragma solidity >=0.5.15;

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
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
	function suck(address, address, uint) external;
    function move(address, address, uint) external;
    function dai(address) external view returns (uint);
}

contract Keg is LibNote {

	// --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; emit NewBrewMaster(usr); }
    function deny(address usr) external note auth { wards[usr] = 0; emit RetiredBrewMaster(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "Keg/not-authorized");
        _;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external note auth { stopped = 1; }
    function start() external note auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    VatLike 	public vat;
    address 	public vow;

    uint public beer; // Total encumbered funds (Available for people to withdraw)

    uint256 constant RAY = 10 ** 27;

    // Accounting for tracking users availale balances
    mapping (address => uint) public mugs;

    // Two-way mapping tracks delegates
    mapping (address => address) public pals;   // Delegate -> Original
    mapping (address => address) public buds;   // Original -> Delegate

    // --- Events ---
    event NewBrewMaster(address brewmaster);
    event RetiredBrewMaster(address brewmaster);
    event BrewBeer(uint256 beer);
    event PourBeer(address bartender, uint256 beer);
    event DrinkingBuddy(address indexed owner, address bud);
    event ByeFelicia(address indexed owner, address bud);
    event JustASip(address bum, uint256 beer);
    event DownTheHatch(address bum, uint256 beer);

    constructor(address vat_, address vow_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        vow = vow_;
        beer = 0;
    }

    // Suck from the vat to the keg to allow for a pool of funds
    function brew(uint wad) external note auth stoppable {
    	vat.suck(address(vow), address(this), mul(wad, RAY));
        emit BrewBeer(wad);
    }

    // Credits people with rights to withdraw funds from the pool
    function pour(address[] calldata bums, uint[] calldata wad) external note auth stoppable {
        require(bums.length == wad.length, "Keg/unequal-payees-and-amounts");
        require(bums.length > 0, "Keg/no-bums");
        uint suds = 0;
        for (uint i = 0; i < wad.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            mugs[bums[i]] = add(mugs[bums[i]], wad[i]);
            suds          = add(suds, wad[i]);
            emit PourBeer(bums[i], wad[i]);
        }
        beer = add(beer, suds);
        require(vat.dai(address(this)) == mul(beer, RAY), "Keg/pour-not-equal-to-brew");
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
        emit DrinkingBuddy(msg.sender, bud);
    }

    // User revokes delegation
    function yank() public {
        require(buds[msg.sender] != address(0), "Keg/no-bud");
        emit ByeFelicia(msg.sender, buds[msg.sender]);
        pals[buds[msg.sender]] = address(0);
        buds[msg.sender] = address(0);
    }

    // User withdraws all funds
    function chug() external {
        uint pint = mugs[msg.sender] + mugs[pals[msg.sender]];
        require(pint != uint256(0), "Keg/too-thirsty-not-enough-beer");
        beer = sub(beer, pint);
        mugs[msg.sender] = 0;
        mugs[pals[msg.sender]] = 0;

        vat.move(address(this), msg.sender, mul(pint, RAY));
        emit DownTheHatch(msg.sender, pint);
    }

    // User withdraws some of their compensation
    // TODO: Handle case where: mugs[pals[msg.sender]] < wad < (mugs[pals[msg.sender]] + mugs[bum])
    // TODO: Handle case where: mugs[pals[msg.sender]] == 0 && mugs[msg.sender] > 0
    function sip(uint256 wad) external {
        // Whose tab are we drinking on
        address bum = pals[msg.sender] != address(0) ? pals[msg.sender] : msg.sender;
        mugs[bum] = sub(mugs[bum], wad);
        beer      = sub(beer, wad);

        vat.move(address(this), msg.sender, mul(wad, RAY));
        emit JustASip(msg.sender, wad);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
    	if (what == "vat") vat = VatLike(addr);
    	else if (what == "vow") vow = addr;
    	else revert("Keg/file-unrecognized-param");
    }
}