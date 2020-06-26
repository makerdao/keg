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
}

contract DaiJoinLike {
	function exit(address, uint) external;
}

contract DSTokenLike {
    function balanceOf(address) public returns (uint);
    function move(address, address, uint) public;
}

contract Keg is LibNote {

	// --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
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

    // --- Stop ---
    uint256 public stopped;
    function stop() external note auth { stopped = 1; }
    function start() external note auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    VatLike 	public vat;
    DaiJoinLike public join;
    DSTokenLike public dai;
    address 	public vow;

    //accounting for tracking users balances
    mapping (address => uint) public mugs;

    //two-way mapping tracks delegates
    mapping (address => address) public pals;   //delegate -> original
    mapping (address => address) public buds;   //original -> delegate

    // --- Events ---
    event DrinkingBuddy(address indexed owner, address delegate);
    event NoNewFriends(address indexed owner, address delegate);
    event JustASip(address bud, address pal, uint256 beer);
    event DownTheHatch(address bud, address pal, uint256 beer);
    ecent BrewBeer(uint256 beer);

    constructor(address vat_, address join_, address dai_, address vow_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        join = DaiJoinLike(join_);
        dai = DSTokenLike(dai_);
        vow = vow_;
    }

    //credit compensation to payees
    //could also merge for loops by doing accounting while summating beer, but weird logic to account first before suck
    function brew(address[] calldata bum, uint[] calldata wad) external note auth stoppable {

    	uint256 beer = 0;

    	require(bum.length == wad.length, "Keg/unequal-payees-and-amounts");
    	for (uint i = 0; i < wad.length; i++) {
    		beer = add(beer, wad[i]);
    	}

        //last param beer is a rad
    	vat.suck(address(vow), address(this), beer);
    	join.exit(address(this), beer);
    	require(dai.balanceOf(address(this)) == beer, "Keg/invalid-dai-balance");

    	for (uint i = 0; i < bum.length; i++) {
    		require(bum[i] != address(0), "Keg/no-address-0");
    		//add balance wad to address in mug
    		mugs[bum[i]] = add(mugs[bum[i]], wad[i]);
    	}
        emit BrewBeer(beer);
    }

    //user delegates compensation to another address
    function pass(address bud) external {
        //original addr -> delegated addr
        buds[msg.sender] = bud;
        //delegated addr -> original addr
        pals[bud] = msg.sender;
        emit DrinkingBuddy(msg.sender, bud);
    }

    //user revokes delegation
    function yank() external {
        address bud;
        bud = buds[msg.sender];
        pals[bud] = address(0);
        buds[msg.sender] = address(0);
        emit NoNewFriends(msg.sender, bud);
    }

    //user withdraws all their compensation
    function chug() external {
        address bum;
        uint256 beer;
        //whose tab are we drinking on
        pals[msg.sender] != address(0) ? bum = pals[msg.sender] : bum = msg.sender;
        beer = mugs[bum];
        require(beer != uint256(0), "Keg/too-thirsty-not-enough-beer");
        mugs[bum] = sub(mugs[bum], beer);
        dai.move(address(this), msg.sender, beer);
        emit DownTheHatch(bum, msg.sender, beer);
    }

    //user withdraws some of their compensation
    function sip(uint256 beer) external {
        address bum;
        //whose tab are we drinking on
        pals[msg.sender] != address(0) ? bum = pals[msg.sender] : bum = msg.sender;
        require(beer <= mugs[msg.sender], "Keg/too-thirsty-not-enough-beer");
        mugs[bum] = sub(mugs[bum], beer);
        dai.move(address(this), msg.sender, beer);
        emit JustASip(bum, msg.sender, beer);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
    	if (what == "vat") vat = VatLike(addr);
    	else if (what == "join") join = DaiJoinLike(addr);
    	else if (what == "dai") dai = DSTokenLike(addr);
    	else if (what == "vow") vow = addr;
    	else revert("Keg/file-unrecognized-param");
    }

}