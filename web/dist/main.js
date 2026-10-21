(function(scope){
'use strict';

function F(arity, fun, wrapper) {
  wrapper.a = arity;
  wrapper.f = fun;
  return wrapper;
}

function F2(fun) {
  return F(2, fun, function(a) { return function(b) { return fun(a,b); }; })
}
function F3(fun) {
  return F(3, fun, function(a) {
    return function(b) { return function(c) { return fun(a, b, c); }; };
  });
}
function F4(fun) {
  return F(4, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return fun(a, b, c, d); }; }; };
  });
}
function F5(fun) {
  return F(5, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return fun(a, b, c, d, e); }; }; }; };
  });
}
function F6(fun) {
  return F(6, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return fun(a, b, c, d, e, f); }; }; }; }; };
  });
}
function F7(fun) {
  return F(7, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return fun(a, b, c, d, e, f, g); }; }; }; }; }; };
  });
}
function F8(fun) {
  return F(8, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) {
    return fun(a, b, c, d, e, f, g, h); }; }; }; }; }; }; };
  });
}
function F9(fun) {
  return F(9, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) { return function(i) {
    return fun(a, b, c, d, e, f, g, h, i); }; }; }; }; }; }; }; };
  });
}

function A2(fun, a, b) {
  return fun.a === 2 ? fun.f(a, b) : fun(a)(b);
}
function A3(fun, a, b, c) {
  return fun.a === 3 ? fun.f(a, b, c) : fun(a)(b)(c);
}
function A4(fun, a, b, c, d) {
  return fun.a === 4 ? fun.f(a, b, c, d) : fun(a)(b)(c)(d);
}
function A5(fun, a, b, c, d, e) {
  return fun.a === 5 ? fun.f(a, b, c, d, e) : fun(a)(b)(c)(d)(e);
}
function A6(fun, a, b, c, d, e, f) {
  return fun.a === 6 ? fun.f(a, b, c, d, e, f) : fun(a)(b)(c)(d)(e)(f);
}
function A7(fun, a, b, c, d, e, f, g) {
  return fun.a === 7 ? fun.f(a, b, c, d, e, f, g) : fun(a)(b)(c)(d)(e)(f)(g);
}
function A8(fun, a, b, c, d, e, f, g, h) {
  return fun.a === 8 ? fun.f(a, b, c, d, e, f, g, h) : fun(a)(b)(c)(d)(e)(f)(g)(h);
}
function A9(fun, a, b, c, d, e, f, g, h, i) {
  return fun.a === 9 ? fun.f(a, b, c, d, e, f, g, h, i) : fun(a)(b)(c)(d)(e)(f)(g)(h)(i);
}




// EQUALITY

function _Utils_eq(x, y)
{
	for (
		var pair, stack = [], isEqual = _Utils_eqHelp(x, y, 0, stack);
		isEqual && (pair = stack.pop());
		isEqual = _Utils_eqHelp(pair.a, pair.b, 0, stack)
		)
	{}

	return isEqual;
}

function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	/**_UNUSED/
	if (x.$ === 'Set_elm_builtin')
	{
		x = $elm$core$Set$toList(x);
		y = $elm$core$Set$toList(y);
	}
	if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	/**/
	if (x.$ < 0)
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	for (var key in x)
	{
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

function _Utils_cmp(x, y, ord)
{
	if (typeof x !== 'object')
	{
		return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
	}

	/**_UNUSED/
	if (x instanceof String)
	{
		var a = x.valueOf();
		var b = y.valueOf();
		return a === b ? 0 : a < b ? -1 : 1;
	}
	//*/

	/**/
	if (typeof x.$ === 'undefined')
	//*/
	/**_UNUSED/
	if (x.$[0] === '#')
	//*/
	{
		return (ord = _Utils_cmp(x.a, y.a))
			? ord
			: (ord = _Utils_cmp(x.b, y.b))
				? ord
				: _Utils_cmp(x.c, y.c);
	}

	// traverse conses until end of a list or a mismatch
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? $elm$core$Basics$LT : n ? $elm$core$Basics$GT : $elm$core$Basics$EQ;
});


// COMMON VALUES

var _Utils_Tuple0 = 0;
var _Utils_Tuple0_UNUSED = { $: '#0' };

function _Utils_Tuple2(a, b) { return { a: a, b: b }; }
function _Utils_Tuple2_UNUSED(a, b) { return { $: '#2', a: a, b: b }; }

function _Utils_Tuple3(a, b, c) { return { a: a, b: b, c: c }; }
function _Utils_Tuple3_UNUSED(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }

function _Utils_chr(c) { return c; }
function _Utils_chr_UNUSED(c) { return new String(c); }


// RECORDS

function _Utils_update(oldRecord, updatedFields)
{
	var newRecord = {};

	for (var key in oldRecord)
	{
		newRecord[key] = oldRecord[key];
	}

	for (var key in updatedFields)
	{
		newRecord[key] = updatedFields[key];
	}

	return newRecord;
}


// APPEND

var _Utils_append = F2(_Utils_ap);

function _Utils_ap(xs, ys)
{
	// append Strings
	if (typeof xs === 'string')
	{
		return xs + ys;
	}

	// append Lists
	if (!xs.b)
	{
		return ys;
	}
	var root = _List_Cons(xs.a, ys);
	xs = xs.b
	for (var curr = root; xs.b; xs = xs.b) // WHILE_CONS
	{
		curr = curr.b = _List_Cons(xs.a, ys);
	}
	return root;
}



var _List_Nil = { $: 0 };
var _List_Nil_UNUSED = { $: '[]' };

function _List_Cons(hd, tl) { return { $: 1, a: hd, b: tl }; }
function _List_Cons_UNUSED(hd, tl) { return { $: '::', a: hd, b: tl }; }


var _List_cons = F2(_List_Cons);

function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

function _List_toArray(xs)
{
	for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
	{
		out.push(xs.a);
	}
	return out;
}

var _List_map2 = F3(function(f, xs, ys)
{
	for (var arr = []; xs.b && ys.b; xs = xs.b, ys = ys.b) // WHILE_CONSES
	{
		arr.push(A2(f, xs.a, ys.a));
	}
	return _List_fromArray(arr);
});

var _List_map3 = F4(function(f, xs, ys, zs)
{
	for (var arr = []; xs.b && ys.b && zs.b; xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A3(f, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map4 = F5(function(f, ws, xs, ys, zs)
{
	for (var arr = []; ws.b && xs.b && ys.b && zs.b; ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A4(f, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map5 = F6(function(f, vs, ws, xs, ys, zs)
{
	for (var arr = []; vs.b && ws.b && xs.b && ys.b && zs.b; vs = vs.b, ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A5(f, vs.a, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_sortBy = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		return _Utils_cmp(f(a), f(b));
	}));
});

var _List_sortWith = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		var ord = A2(f, a, b);
		return ord === $elm$core$Basics$EQ ? 0 : ord === $elm$core$Basics$LT ? -1 : 1;
	}));
});



var _JsArray_empty = [];

function _JsArray_singleton(value)
{
    return [value];
}

function _JsArray_length(array)
{
    return array.length;
}

var _JsArray_initialize = F3(function(size, offset, func)
{
    var result = new Array(size);

    for (var i = 0; i < size; i++)
    {
        result[i] = func(offset + i);
    }

    return result;
});

var _JsArray_initializeFromList = F2(function (max, ls)
{
    var result = new Array(max);

    for (var i = 0; i < max && ls.b; i++)
    {
        result[i] = ls.a;
        ls = ls.b;
    }

    result.length = i;
    return _Utils_Tuple2(result, ls);
});

var _JsArray_unsafeGet = F2(function(index, array)
{
    return array[index];
});

var _JsArray_unsafeSet = F3(function(index, value, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[index] = value;
    return result;
});

var _JsArray_push = F2(function(value, array)
{
    var length = array.length;
    var result = new Array(length + 1);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[length] = value;
    return result;
});

var _JsArray_foldl = F3(function(func, acc, array)
{
    var length = array.length;

    for (var i = 0; i < length; i++)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_foldr = F3(function(func, acc, array)
{
    for (var i = array.length - 1; i >= 0; i--)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_map = F2(function(func, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = func(array[i]);
    }

    return result;
});

var _JsArray_indexedMap = F3(function(func, offset, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = A2(func, offset + i, array[i]);
    }

    return result;
});

var _JsArray_slice = F3(function(from, to, array)
{
    return array.slice(from, to);
});

var _JsArray_appendN = F3(function(n, dest, source)
{
    var destLen = dest.length;
    var itemsToCopy = n - destLen;

    if (itemsToCopy > source.length)
    {
        itemsToCopy = source.length;
    }

    var size = destLen + itemsToCopy;
    var result = new Array(size);

    for (var i = 0; i < destLen; i++)
    {
        result[i] = dest[i];
    }

    for (var i = 0; i < itemsToCopy; i++)
    {
        result[i + destLen] = source[i];
    }

    return result;
});



// LOG

var _Debug_log = F2(function(tag, value)
{
	return value;
});

var _Debug_log_UNUSED = F2(function(tag, value)
{
	console.log(tag + ': ' + _Debug_toString(value));
	return value;
});


// TODOS

function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}


// TO STRING

function _Debug_toString(value)
{
	return '<internals>';
}

function _Debug_toString_UNUSED(value)
{
	return _Debug_toAnsiString(false, value);
}

function _Debug_toAnsiString(ansi, value)
{
	if (typeof value === 'function')
	{
		return _Debug_internalColor(ansi, '<function>');
	}

	if (typeof value === 'boolean')
	{
		return _Debug_ctorColor(ansi, value ? 'True' : 'False');
	}

	if (typeof value === 'number')
	{
		return _Debug_numberColor(ansi, value + '');
	}

	if (value instanceof String)
	{
		return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
	}

	if (typeof value === 'string')
	{
		return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
	}

	if (typeof value === 'object' && '$' in value)
	{
		var tag = value.$;

		if (typeof tag === 'number')
		{
			return _Debug_internalColor(ansi, '<internals>');
		}

		if (tag[0] === '#')
		{
			var output = [];
			for (var k in value)
			{
				if (k === '$') continue;
				output.push(_Debug_toAnsiString(ansi, value[k]));
			}
			return '(' + output.join(',') + ')';
		}

		if (tag === 'Set_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Set')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Set$toList(value));
		}

		if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Dict')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Dict$toList(value));
		}

		if (tag === 'Array_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Array')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Array$toList(value));
		}

		if (tag === '::' || tag === '[]')
		{
			var output = '[';

			value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

			for (; value.b; value = value.b) // WHILE_CONS
			{
				output += ',' + _Debug_toAnsiString(ansi, value.a);
			}
			return output + ']';
		}

		var output = '';
		for (var i in value)
		{
			if (i === '$') continue;
			var str = _Debug_toAnsiString(ansi, value[i]);
			var c0 = str[0];
			var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
			output += ' ' + (parenless ? str : '(' + str + ')');
		}
		return _Debug_ctorColor(ansi, tag) + output;
	}

	if (typeof DataView === 'function' && value instanceof DataView)
	{
		return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
	}

	if (typeof File !== 'undefined' && value instanceof File)
	{
		return _Debug_internalColor(ansi, '<' + value.name + '>');
	}

	if (typeof value === 'object')
	{
		var output = [];
		for (var key in value)
		{
			var field = key[0] === '_' ? key.slice(1) : key;
			output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
		}
		if (output.length === 0)
		{
			return '{}';
		}
		return '{ ' + output.join(', ') + ' }';
	}

	return _Debug_internalColor(ansi, '<internals>');
}

function _Debug_addSlashes(str, isChar)
{
	var s = str
		.replace(/\\/g, '\\\\')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t')
		.replace(/\r/g, '\\r')
		.replace(/\v/g, '\\v')
		.replace(/\0/g, '\\0');

	if (isChar)
	{
		return s.replace(/\'/g, '\\\'');
	}
	else
	{
		return s.replace(/\"/g, '\\"');
	}
}

function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}


// CRASH


function _Debug_crash(identifier)
{
	throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
}


function _Debug_crash_UNUSED(identifier, fact1, fact2, fact3, fact4)
{
	switch(identifier)
	{
		case 0:
			throw new Error('What node should I take over? In JavaScript I need something like:\n\n    Elm.Main.init({\n        node: document.getElementById("elm-node")\n    })\n\nYou need to do this with any Browser.sandbox or Browser.element program.');

		case 1:
			throw new Error('Browser.application programs cannot handle URLs like this:\n\n    ' + document.location.href + '\n\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.');

		case 2:
			var jsonErrorString = fact1;
			throw new Error('Problem with the flags given to your Elm program on initialization.\n\n' + jsonErrorString);

		case 3:
			var portName = fact1;
			throw new Error('There can only be one port named `' + portName + '`, but your program has multiple.');

		case 4:
			var portName = fact1;
			var problem = fact2;
			throw new Error('Trying to send an unexpected type of value through port `' + portName + '`:\n' + problem);

		case 5:
			throw new Error('Trying to use `(==)` on functions.\nThere is no way to know if functions are "the same" in the Elm sense.\nRead more about this at https://package.elm-lang.org/packages/elm/core/latest/Basics#== which describes why it is this way and what the better version will look like.');

		case 6:
			var moduleName = fact1;
			throw new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');

		case 8:
			var moduleName = fact1;
			var region = fact2;
			var message = fact3;
			throw new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\n\n' + message);

		case 9:
			var moduleName = fact1;
			var region = fact2;
			var value = fact3;
			var message = fact4;
			throw new Error(
				'TODO in module `' + moduleName + '` from the `case` expression '
				+ _Debug_regionToString(region) + '\n\nIt received the following value:\n\n    '
				+ _Debug_toString(value).replace('\n', '\n    ')
				+ '\n\nBut the branch that handles it says:\n\n    ' + message.replace('\n', '\n    ')
			);

		case 10:
			throw new Error('Bug in https://github.com/elm/virtual-dom/issues');

		case 11:
			throw new Error('Cannot perform mod 0. Division by zero error.');
	}
}

function _Debug_regionToString(region)
{
	if (region.bp.ar === region.bD.ar)
	{
		return 'on line ' + region.bp.ar;
	}
	return 'on lines ' + region.bp.ar + ' through ' + region.bD.ar;
}



// MATH

var _Basics_add = F2(function(a, b) { return a + b; });
var _Basics_sub = F2(function(a, b) { return a - b; });
var _Basics_mul = F2(function(a, b) { return a * b; });
var _Basics_fdiv = F2(function(a, b) { return a / b; });
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
var _Basics_pow = F2(Math.pow);

var _Basics_remainderBy = F2(function(b, a) { return a % b; });

// https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/divmodnote-letter.pdf
var _Basics_modBy = F2(function(modulus, x)
{
	var answer = x % modulus;
	return modulus === 0
		? _Debug_crash(11)
		:
	((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0))
		? answer + modulus
		: answer;
});


// TRIGONOMETRY

var _Basics_pi = Math.PI;
var _Basics_e = Math.E;
var _Basics_cos = Math.cos;
var _Basics_sin = Math.sin;
var _Basics_tan = Math.tan;
var _Basics_acos = Math.acos;
var _Basics_asin = Math.asin;
var _Basics_atan = Math.atan;
var _Basics_atan2 = F2(Math.atan2);


// MORE MATH

function _Basics_toFloat(x) { return x; }
function _Basics_truncate(n) { return n | 0; }
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

var _Basics_ceiling = Math.ceil;
var _Basics_floor = Math.floor;
var _Basics_round = Math.round;
var _Basics_sqrt = Math.sqrt;
var _Basics_log = Math.log;
var _Basics_isNaN = isNaN;


// BOOLEANS

function _Basics_not(bool) { return !bool; }
var _Basics_and = F2(function(a, b) { return a && b; });
var _Basics_or  = F2(function(a, b) { return a || b; });
var _Basics_xor = F2(function(a, b) { return a !== b; });



var _String_cons = F2(function(chr, str)
{
	return chr + str;
});

function _String_uncons(string)
{
	var word = string.charCodeAt(0);
	return !isNaN(word)
		? $elm$core$Maybe$Just(
			0xD800 <= word && word <= 0xDBFF
				? _Utils_Tuple2(_Utils_chr(string[0] + string[1]), string.slice(2))
				: _Utils_Tuple2(_Utils_chr(string[0]), string.slice(1))
		)
		: $elm$core$Maybe$Nothing;
}

var _String_append = F2(function(a, b)
{
	return a + b;
});

function _String_length(str)
{
	return str.length;
}

var _String_map = F2(function(func, string)
{
	var len = string.length;
	var array = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = string.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			array[i] = func(_Utils_chr(string[i] + string[i+1]));
			i += 2;
			continue;
		}
		array[i] = func(_Utils_chr(string[i]));
		i++;
	}
	return array.join('');
});

var _String_filter = F2(function(isGood, str)
{
	var arr = [];
	var len = str.length;
	var i = 0;
	while (i < len)
	{
		var char = str[i];
		var word = str.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += str[i];
			i++;
		}

		if (isGood(_Utils_chr(char)))
		{
			arr.push(char);
		}
	}
	return arr.join('');
});

function _String_reverse(str)
{
	var len = str.length;
	var arr = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = str.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			arr[len - i] = str[i + 1];
			i++;
			arr[len - i] = str[i - 1];
			i++;
		}
		else
		{
			arr[len - i] = str[i];
			i++;
		}
	}
	return arr.join('');
}

var _String_foldl = F3(function(func, state, string)
{
	var len = string.length;
	var i = 0;
	while (i < len)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += string[i];
			i++;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_foldr = F3(function(func, state, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_split = F2(function(sep, str)
{
	return str.split(sep);
});

var _String_join = F2(function(sep, strs)
{
	return strs.join(sep);
});

var _String_slice = F3(function(start, end, str) {
	return str.slice(start, end);
});

function _String_trim(str)
{
	return str.trim();
}

function _String_trimLeft(str)
{
	return str.replace(/^\s+/, '');
}

function _String_trimRight(str)
{
	return str.replace(/\s+$/, '');
}

function _String_words(str)
{
	return _List_fromArray(str.trim().split(/\s+/g));
}

function _String_lines(str)
{
	return _List_fromArray(str.split(/\r\n|\r|\n/g));
}

function _String_toUpper(str)
{
	return str.toUpperCase();
}

function _String_toLower(str)
{
	return str.toLowerCase();
}

var _String_any = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (isGood(_Utils_chr(char)))
		{
			return true;
		}
	}
	return false;
});

var _String_all = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (!isGood(_Utils_chr(char)))
		{
			return false;
		}
	}
	return true;
});

var _String_contains = F2(function(sub, str)
{
	return str.indexOf(sub) > -1;
});

var _String_startsWith = F2(function(sub, str)
{
	return str.indexOf(sub) === 0;
});

var _String_endsWith = F2(function(sub, str)
{
	return str.length >= sub.length &&
		str.lastIndexOf(sub) === str.length - sub.length;
});

var _String_indexes = F2(function(sub, str)
{
	var subLen = sub.length;

	if (subLen < 1)
	{
		return _List_Nil;
	}

	var i = 0;
	var is = [];

	while ((i = str.indexOf(sub, i)) > -1)
	{
		is.push(i);
		i = i + subLen;
	}

	return _List_fromArray(is);
});


// TO STRING

function _String_fromNumber(number)
{
	return number + '';
}


// INT CONVERSIONS

function _String_toInt(str)
{
	var total = 0;
	var code0 = str.charCodeAt(0);
	var start = code0 == 0x2B /* + */ || code0 == 0x2D /* - */ ? 1 : 0;

	for (var i = start; i < str.length; ++i)
	{
		var code = str.charCodeAt(i);
		if (code < 0x30 || 0x39 < code)
		{
			return $elm$core$Maybe$Nothing;
		}
		total = 10 * total + code - 0x30;
	}

	return i == start
		? $elm$core$Maybe$Nothing
		: $elm$core$Maybe$Just(code0 == 0x2D ? -total : total);
}


// FLOAT CONVERSIONS

function _String_toFloat(s)
{
	// check if it is a hex, octal, or binary number
	if (s.length === 0 || /[\sxbo]/.test(s))
	{
		return $elm$core$Maybe$Nothing;
	}
	var n = +s;
	// faster isNaN check
	return n === n ? $elm$core$Maybe$Just(n) : $elm$core$Maybe$Nothing;
}

function _String_fromList(chars)
{
	return _List_toArray(chars).join('');
}




function _Char_toCode(char)
{
	var code = char.charCodeAt(0);
	if (0xD800 <= code && code <= 0xDBFF)
	{
		return (code - 0xD800) * 0x400 + char.charCodeAt(1) - 0xDC00 + 0x10000
	}
	return code;
}

function _Char_fromCode(code)
{
	return _Utils_chr(
		(code < 0 || 0x10FFFF < code)
			? '\uFFFD'
			:
		(code <= 0xFFFF)
			? String.fromCharCode(code)
			:
		(code -= 0x10000,
			String.fromCharCode(Math.floor(code / 0x400) + 0xD800, code % 0x400 + 0xDC00)
		)
	);
}

function _Char_toUpper(char)
{
	return _Utils_chr(char.toUpperCase());
}

function _Char_toLower(char)
{
	return _Utils_chr(char.toLowerCase());
}

function _Char_toLocaleUpper(char)
{
	return _Utils_chr(char.toLocaleUpperCase());
}

function _Char_toLocaleLower(char)
{
	return _Utils_chr(char.toLocaleLowerCase());
}



/**_UNUSED/
function _Json_errorToString(error)
{
	return $elm$json$Json$Decode$errorToString(error);
}
//*/


// CORE DECODERS

function _Json_succeed(msg)
{
	return {
		$: 0,
		a: msg
	};
}

function _Json_fail(msg)
{
	return {
		$: 1,
		a: msg
	};
}

function _Json_decodePrim(decoder)
{
	return { $: 2, b: decoder };
}

var _Json_decodeInt = _Json_decodePrim(function(value) {
	return (typeof value !== 'number')
		? _Json_expecting('an INT', value)
		:
	(-2147483647 < value && value < 2147483647 && (value | 0) === value)
		? $elm$core$Result$Ok(value)
		:
	(isFinite(value) && !(value % 1))
		? $elm$core$Result$Ok(value)
		: _Json_expecting('an INT', value);
});

var _Json_decodeBool = _Json_decodePrim(function(value) {
	return (typeof value === 'boolean')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a BOOL', value);
});

var _Json_decodeFloat = _Json_decodePrim(function(value) {
	return (typeof value === 'number')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FLOAT', value);
});

var _Json_decodeValue = _Json_decodePrim(function(value) {
	return $elm$core$Result$Ok(_Json_wrap(value));
});

var _Json_decodeString = _Json_decodePrim(function(value) {
	return (typeof value === 'string')
		? $elm$core$Result$Ok(value)
		: (value instanceof String)
			? $elm$core$Result$Ok(value + '')
			: _Json_expecting('a STRING', value);
});

function _Json_decodeList(decoder) { return { $: 3, b: decoder }; }
function _Json_decodeArray(decoder) { return { $: 4, b: decoder }; }

function _Json_decodeNull(value) { return { $: 5, c: value }; }

var _Json_decodeField = F2(function(field, decoder)
{
	return {
		$: 6,
		d: field,
		b: decoder
	};
});

var _Json_decodeIndex = F2(function(index, decoder)
{
	return {
		$: 7,
		e: index,
		b: decoder
	};
});

function _Json_decodeKeyValuePairs(decoder)
{
	return {
		$: 8,
		b: decoder
	};
}

function _Json_mapMany(f, decoders)
{
	return {
		$: 9,
		f: f,
		g: decoders
	};
}

var _Json_andThen = F2(function(callback, decoder)
{
	return {
		$: 10,
		b: decoder,
		h: callback
	};
});

function _Json_oneOf(decoders)
{
	return {
		$: 11,
		g: decoders
	};
}


// DECODING OBJECTS

var _Json_map1 = F2(function(f, d1)
{
	return _Json_mapMany(f, [d1]);
});

var _Json_map2 = F3(function(f, d1, d2)
{
	return _Json_mapMany(f, [d1, d2]);
});

var _Json_map3 = F4(function(f, d1, d2, d3)
{
	return _Json_mapMany(f, [d1, d2, d3]);
});

var _Json_map4 = F5(function(f, d1, d2, d3, d4)
{
	return _Json_mapMany(f, [d1, d2, d3, d4]);
});

var _Json_map5 = F6(function(f, d1, d2, d3, d4, d5)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5]);
});

var _Json_map6 = F7(function(f, d1, d2, d3, d4, d5, d6)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6]);
});

var _Json_map7 = F8(function(f, d1, d2, d3, d4, d5, d6, d7)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7]);
});

var _Json_map8 = F9(function(f, d1, d2, d3, d4, d5, d6, d7, d8)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7, d8]);
});


// DECODE

var _Json_runOnString = F2(function(decoder, string)
{
	try
	{
		var value = JSON.parse(string);
		return _Json_runHelp(decoder, value);
	}
	catch (e)
	{
		return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'This is not valid JSON! ' + e.message, _Json_wrap(string)));
	}
});

var _Json_run = F2(function(decoder, value)
{
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

function _Json_runHelp(decoder, value)
{
	switch (decoder.$)
	{
		case 2:
			return decoder.b(value);

		case 5:
			return (value === null)
				? $elm$core$Result$Ok(decoder.c)
				: _Json_expecting('null', value);

		case 3:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('a LIST', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _List_fromArray);

		case 4:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _Json_toElmArray);

		case 6:
			var field = decoder.d;
			if (typeof value !== 'object' || value === null || !(field in value))
			{
				return _Json_expecting('an OBJECT with a field named `' + field + '`', value);
			}
			var result = _Json_runHelp(decoder.b, value[field]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, field, result.a));

		case 7:
			var index = decoder.e;
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			if (index >= value.length)
			{
				return _Json_expecting('a LONGER array. Need index ' + index + ' but only see ' + value.length + ' entries', value);
			}
			var result = _Json_runHelp(decoder.b, value[index]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, index, result.a));

		case 8:
			if (typeof value !== 'object' || value === null || _Json_isArray(value))
			{
				return _Json_expecting('an OBJECT', value);
			}

			var keyValuePairs = _List_Nil;
			// TODO test perf of Object.keys and switch when support is good enough
			for (var key in value)
			{
				if (Object.prototype.hasOwnProperty.call(value, key))
				{
					var result = _Json_runHelp(decoder.b, value[key]);
					if (!$elm$core$Result$isOk(result))
					{
						return $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, key, result.a));
					}
					keyValuePairs = _List_Cons(_Utils_Tuple2(key, result.a), keyValuePairs);
				}
			}
			return $elm$core$Result$Ok($elm$core$List$reverse(keyValuePairs));

		case 9:
			var answer = decoder.f;
			var decoders = decoder.g;
			for (var i = 0; i < decoders.length; i++)
			{
				var result = _Json_runHelp(decoders[i], value);
				if (!$elm$core$Result$isOk(result))
				{
					return result;
				}
				answer = answer(result.a);
			}
			return $elm$core$Result$Ok(answer);

		case 10:
			var result = _Json_runHelp(decoder.b, value);
			return (!$elm$core$Result$isOk(result))
				? result
				: _Json_runHelp(decoder.h(result.a), value);

		case 11:
			var errors = _List_Nil;
			for (var temp = decoder.g; temp.b; temp = temp.b) // WHILE_CONS
			{
				var result = _Json_runHelp(temp.a, value);
				if ($elm$core$Result$isOk(result))
				{
					return result;
				}
				errors = _List_Cons(result.a, errors);
			}
			return $elm$core$Result$Err($elm$json$Json$Decode$OneOf($elm$core$List$reverse(errors)));

		case 1:
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, decoder.a, _Json_wrap(value)));

		case 0:
			return $elm$core$Result$Ok(decoder.a);
	}
}

function _Json_runArrayDecoder(decoder, value, toElmValue)
{
	var len = value.length;
	var array = new Array(len);
	for (var i = 0; i < len; i++)
	{
		var result = _Json_runHelp(decoder, value[i]);
		if (!$elm$core$Result$isOk(result))
		{
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, i, result.a));
		}
		array[i] = result.a;
	}
	return $elm$core$Result$Ok(toElmValue(array));
}

function _Json_isArray(value)
{
	return Array.isArray(value) || (typeof FileList !== 'undefined' && value instanceof FileList);
}

function _Json_toElmArray(array)
{
	return A2($elm$core$Array$initialize, array.length, function(i) { return array[i]; });
}

function _Json_expecting(type, value)
{
	return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'Expecting ' + type, _Json_wrap(value)));
}


// EQUALITY

function _Json_equality(x, y)
{
	if (x === y)
	{
		return true;
	}

	if (x.$ !== y.$)
	{
		return false;
	}

	switch (x.$)
	{
		case 0:
		case 1:
			return x.a === y.a;

		case 2:
			return x.b === y.b;

		case 5:
			return x.c === y.c;

		case 3:
		case 4:
		case 8:
			return _Json_equality(x.b, y.b);

		case 6:
			return x.d === y.d && _Json_equality(x.b, y.b);

		case 7:
			return x.e === y.e && _Json_equality(x.b, y.b);

		case 9:
			return x.f === y.f && _Json_listEquality(x.g, y.g);

		case 10:
			return x.h === y.h && _Json_equality(x.b, y.b);

		case 11:
			return _Json_listEquality(x.g, y.g);
	}
}

function _Json_listEquality(aDecoders, bDecoders)
{
	var len = aDecoders.length;
	if (len !== bDecoders.length)
	{
		return false;
	}
	for (var i = 0; i < len; i++)
	{
		if (!_Json_equality(aDecoders[i], bDecoders[i]))
		{
			return false;
		}
	}
	return true;
}


// ENCODE

var _Json_encode = F2(function(indentLevel, value)
{
	return JSON.stringify(_Json_unwrap(value), null, indentLevel) + '';
});

function _Json_wrap_UNUSED(value) { return { $: 0, a: value }; }
function _Json_unwrap_UNUSED(value) { return value.a; }

function _Json_wrap(value) { return value; }
function _Json_unwrap(value) { return value; }

function _Json_emptyArray() { return []; }
function _Json_emptyObject() { return {}; }

var _Json_addField = F3(function(key, value, object)
{
	var unwrapped = _Json_unwrap(value);
	if (!(key === 'toJSON' && typeof unwrapped === 'function'))
	{
		object[key] = unwrapped;
	}
	return object;
});

function _Json_addEntry(func)
{
	return F2(function(entry, array)
	{
		array.push(_Json_unwrap(func(entry)));
		return array;
	});
}

var _Json_encodeNull = _Json_wrap(null);



// TASKS

function _Scheduler_succeed(value)
{
	return {
		$: 0,
		a: value
	};
}

function _Scheduler_fail(error)
{
	return {
		$: 1,
		a: error
	};
}

function _Scheduler_binding(callback)
{
	return {
		$: 2,
		b: callback,
		c: null
	};
}

var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: 3,
		b: callback,
		d: task
	};
});

var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: 4,
		b: callback,
		d: task
	};
});

function _Scheduler_receive(callback)
{
	return {
		$: 5,
		b: callback
	};
}


// PROCESSES

var _Scheduler_guid = 0;

function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		e: _Scheduler_guid++,
		f: task,
		g: null,
		h: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

function _Scheduler_rawSend(proc, msg)
{
	proc.h.push(msg);
	_Scheduler_enqueue(proc);
}

var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.f;
		if (task.$ === 2 && task.c)
		{
			task.c();
		}

		proc.f = null;

		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
}


/* STEP PROCESSES

type alias Process =
  { $ : tag
  , id : unique_id
  , root : Task
  , stack : null | { $: SUCCEED | FAIL, a: callback, b: stack }
  , mailbox : [msg]
  }

*/


var _Scheduler_working = false;
var _Scheduler_queue = [];


function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	while (proc = _Scheduler_queue.shift())
	{
		_Scheduler_step(proc);
	}
	_Scheduler_working = false;
}


function _Scheduler_step(proc)
{
	while (proc.f)
	{
		var rootTag = proc.f.$;
		if (rootTag === 0 || rootTag === 1)
		{
			while (proc.g && proc.g.$ !== rootTag)
			{
				proc.g = proc.g.i;
			}
			if (!proc.g)
			{
				return;
			}
			proc.f = proc.g.b(proc.f.a);
			proc.g = proc.g.i;
		}
		else if (rootTag === 2)
		{
			proc.f.c = proc.f.b(function(newRoot) {
				proc.f = newRoot;
				_Scheduler_enqueue(proc);
			});
			return;
		}
		else if (rootTag === 5)
		{
			if (proc.h.length === 0)
			{
				return;
			}
			proc.f = proc.f.b(proc.h.shift());
		}
		else // if (rootTag === 3 || rootTag === 4)
		{
			proc.g = {
				$: rootTag === 3 ? 0 : 1,
				b: proc.f.b,
				i: proc.g
			};
			proc.f = proc.f.d;
		}
	}
}



function _Process_sleep(time)
{
	return _Scheduler_binding(function(callback) {
		var id = setTimeout(function() {
			callback(_Scheduler_succeed(_Utils_Tuple0));
		}, time);

		return function() { clearTimeout(id); };
	});
}




// PROGRAMS


var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.cY,
		impl.dy,
		impl.dt,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	$elm$core$Result$isOk(result) || _Debug_crash(2 /**_UNUSED/, _Json_errorToString(result.a) /**/);
	var managers = {};
	var initPair = init(result.a);
	var model = initPair.a;
	var stepper = stepperBuilder(sendToApp, model);
	var ports = _Platform_setupEffects(managers, sendToApp);

	function sendToApp(msg, viewMetadata)
	{
		var pair = A2(update, msg, model);
		stepper(model = pair.a, viewMetadata);
		_Platform_enqueueEffects(managers, pair.b, subscriptions(model));
	}

	_Platform_enqueueEffects(managers, initPair.b, subscriptions(model));

	return ports ? { ports: ports } : {};
}



// TRACK PRELOADS
//
// This is used by code in elm/browser and elm/http
// to register any HTTP requests that are triggered by init.
//


var _Platform_preload;


function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


var _Platform_effectManagers = {};


function _Platform_setupEffects(managers, sendToApp)
{
	var ports;

	// setup all necessary effect managers
	for (var key in _Platform_effectManagers)
	{
		var manager = _Platform_effectManagers[key];

		if (manager.a)
		{
			ports = ports || {};
			ports[key] = manager.a(key, sendToApp);
		}

		managers[key] = _Platform_instantiateManager(manager, sendToApp);
	}

	return ports;
}


function _Platform_createManager(init, onEffects, onSelfMsg, cmdMap, subMap)
{
	return {
		b: init,
		c: onEffects,
		d: onSelfMsg,
		e: cmdMap,
		f: subMap
	};
}


function _Platform_instantiateManager(info, sendToApp)
{
	var router = {
		g: sendToApp,
		h: undefined
	};

	var onEffects = info.c;
	var onSelfMsg = info.d;
	var cmdMap = info.e;
	var subMap = info.f;

	function loop(state)
	{
		return A2(_Scheduler_andThen, loop, _Scheduler_receive(function(msg)
		{
			var value = msg.a;

			if (msg.$ === 0)
			{
				return A3(onSelfMsg, router, value, state);
			}

			return cmdMap && subMap
				? A4(onEffects, router, value.i, value.j, state)
				: A3(onEffects, router, cmdMap ? value.i : value.j, state);
		}));
	}

	return router.h = _Scheduler_rawSpawn(A2(_Scheduler_andThen, loop, info.b));
}



// ROUTING


var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.g(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.h, {
		$: 0,
		a: msg
	});
});



// BAGS


function _Platform_leaf(home)
{
	return function(value)
	{
		return {
			$: 1,
			k: home,
			l: value
		};
	};
}


function _Platform_batch(list)
{
	return {
		$: 2,
		m: list
	};
}


var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: 3,
		n: tagger,
		o: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS
//
// Effects must be queued!
//
// Say your init contains a synchronous command, like Time.now or Time.here
//
//   - This will produce a batch of effects (FX_1)
//   - The synchronous task triggers the subsequent `update` call
//   - This will produce a batch of effects (FX_2)
//
// If we just start dispatching FX_2, subscriptions from FX_2 can be processed
// before subscriptions from FX_1. No good! Earlier versions of this code had
// this problem, leading to these reports:
//
//   https://github.com/elm/core/issues/980
//   https://github.com/elm/core/pull/981
//   https://github.com/elm/compiler/issues/1776
//
// The queue is necessary to avoid ordering issues for synchronous commands.


// Why use true/false here? Why not just check the length of the queue?
// The goal is to detect "are we currently dispatching effects?" If we
// are, we need to bail and let the ongoing while loop handle things.
//
// Now say the queue has 1 element. When we dequeue the final element,
// the queue will be empty, but we are still actively dispatching effects.
// So you could get queue jumping in a really tricky category of cases.
//
var _Platform_effectsQueue = [];
var _Platform_effectsActive = false;


function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ p: managers, q: cmdBag, r: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	for (var fx; fx = _Platform_effectsQueue.shift(); )
	{
		_Platform_dispatchEffects(fx.p, fx.q, fx.r);
	}
	_Platform_effectsActive = false;
}


function _Platform_dispatchEffects(managers, cmdBag, subBag)
{
	var effectsDict = {};
	_Platform_gatherEffects(true, cmdBag, effectsDict, null);
	_Platform_gatherEffects(false, subBag, effectsDict, null);

	for (var home in managers)
	{
		_Scheduler_rawSend(managers[home], {
			$: 'fx',
			a: effectsDict[home] || { i: _List_Nil, j: _List_Nil }
		});
	}
}


function _Platform_gatherEffects(isCmd, bag, effectsDict, taggers)
{
	switch (bag.$)
	{
		case 1:
			var home = bag.k;
			var effect = _Platform_toEffect(isCmd, home, taggers, bag.l);
			effectsDict[home] = _Platform_insert(isCmd, effect, effectsDict[home]);
			return;

		case 2:
			for (var list = bag.m; list.b; list = list.b) // WHILE_CONS
			{
				_Platform_gatherEffects(isCmd, list.a, effectsDict, taggers);
			}
			return;

		case 3:
			_Platform_gatherEffects(isCmd, bag.o, effectsDict, {
				s: bag.n,
				t: taggers
			});
			return;
	}
}


function _Platform_toEffect(isCmd, home, taggers, value)
{
	function applyTaggers(x)
	{
		for (var temp = taggers; temp; temp = temp.t)
		{
			x = temp.s(x);
		}
		return x;
	}

	var map = isCmd
		? _Platform_effectManagers[home].e
		: _Platform_effectManagers[home].f;

	return A2(map, applyTaggers, value)
}


function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { i: _List_Nil, j: _List_Nil };

	isCmd
		? (effects.i = _List_Cons(newEffect, effects.i))
		: (effects.j = _List_Cons(newEffect, effects.j));

	return effects;
}



// PORTS


function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


function _Platform_outgoingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		e: _Platform_outgoingPortMap,
		u: converter,
		a: _Platform_setupOutgoingPort
	};
	return _Platform_leaf(name);
}


var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


function _Platform_setupOutgoingPort(name)
{
	var subs = [];
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Process_sleep(0);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, cmdList, state)
	{
		for ( ; cmdList.b; cmdList = cmdList.b) // WHILE_CONS
		{
			// grab a separate reference to subs in case unsubscribe is called
			var currentSubs = subs;
			var value = _Json_unwrap(converter(cmdList.a));
			for (var i = 0; i < currentSubs.length; i++)
			{
				currentSubs[i](value);
			}
		}
		return init;
	});

	// PUBLIC API

	function subscribe(callback)
	{
		subs.push(callback);
	}

	function unsubscribe(callback)
	{
		// copy subs into a new array in case unsubscribe is called within a
		// subscribed callback
		subs = subs.slice();
		var index = subs.indexOf(callback);
		if (index >= 0)
		{
			subs.splice(index, 1);
		}
	}

	return {
		subscribe: subscribe,
		unsubscribe: unsubscribe
	};
}



// INCOMING PORTS


function _Platform_incomingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		f: _Platform_incomingPortMap,
		u: converter,
		a: _Platform_setupIncomingPort
	};
	return _Platform_leaf(name);
}


var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


function _Platform_setupIncomingPort(name, sendToApp)
{
	var subs = _List_Nil;
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Scheduler_succeed(null);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, subList, state)
	{
		subs = subList;
		return init;
	});

	// PUBLIC API

	function send(incomingValue)
	{
		var result = A2(_Json_run, converter, _Json_wrap(incomingValue));

		$elm$core$Result$isOk(result) || _Debug_crash(4, name, result.a);

		var value = result.a;
		for (var temp = subs; temp.b; temp = temp.b) // WHILE_CONS
		{
			sendToApp(temp.a(value));
		}
	}

	return { send: send };
}



// EXPORT ELM MODULES
//
// Have DEBUG and PROD versions so that we can (1) give nicer errors in
// debug mode and (2) not pay for the bits needed for that in prod mode.
//


function _Platform_export(exports)
{
	scope['Elm']
		? _Platform_mergeExportsProd(scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsProd(obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6)
				: _Platform_mergeExportsProd(obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}


function _Platform_export_UNUSED(exports)
{
	scope['Elm']
		? _Platform_mergeExportsDebug('Elm', scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsDebug(moduleName, obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6, moduleName)
				: _Platform_mergeExportsDebug(moduleName + '.' + name, obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}




// HELPERS


var _VirtualDom_divertHrefToApp;

var _VirtualDom_doc = typeof document !== 'undefined' ? document : {};


function _VirtualDom_appendChild(parent, child)
{
	parent.appendChild(child);
}

var _VirtualDom_init = F4(function(virtualNode, flagDecoder, debugMetadata, args)
{
	// NOTE: this function needs _Platform_export available to work

	/**/
	var node = args['node'];
	//*/
	/**_UNUSED/
	var node = args && args['node'] ? args['node'] : _Debug_crash(0);
	//*/

	node.parentNode.replaceChild(
		_VirtualDom_render(virtualNode, function() {}),
		node
	);

	return {};
});



// TEXT


function _VirtualDom_text(string)
{
	return {
		$: 0,
		a: string
	};
}



// NODE


var _VirtualDom_nodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 1,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_node = _VirtualDom_nodeNS(undefined);



// KEYED NODE


var _VirtualDom_keyedNodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 2,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_keyedNode = _VirtualDom_keyedNodeNS(undefined);



// CUSTOM


function _VirtualDom_custom(factList, model, render, diff)
{
	return {
		$: 3,
		d: _VirtualDom_organizeFacts(factList),
		g: model,
		h: render,
		i: diff
	};
}



// MAP


var _VirtualDom_map = F2(function(tagger, node)
{
	return {
		$: 4,
		j: tagger,
		k: node,
		b: 1 + (node.b || 0)
	};
});



// LAZY


function _VirtualDom_thunk(refs, thunk)
{
	return {
		$: 5,
		l: refs,
		m: thunk,
		k: undefined
	};
}

var _VirtualDom_lazy = F2(function(func, a)
{
	return _VirtualDom_thunk([func, a], function() {
		return func(a);
	});
});

var _VirtualDom_lazy2 = F3(function(func, a, b)
{
	return _VirtualDom_thunk([func, a, b], function() {
		return A2(func, a, b);
	});
});

var _VirtualDom_lazy3 = F4(function(func, a, b, c)
{
	return _VirtualDom_thunk([func, a, b, c], function() {
		return A3(func, a, b, c);
	});
});

var _VirtualDom_lazy4 = F5(function(func, a, b, c, d)
{
	return _VirtualDom_thunk([func, a, b, c, d], function() {
		return A4(func, a, b, c, d);
	});
});

var _VirtualDom_lazy5 = F6(function(func, a, b, c, d, e)
{
	return _VirtualDom_thunk([func, a, b, c, d, e], function() {
		return A5(func, a, b, c, d, e);
	});
});

var _VirtualDom_lazy6 = F7(function(func, a, b, c, d, e, f)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f], function() {
		return A6(func, a, b, c, d, e, f);
	});
});

var _VirtualDom_lazy7 = F8(function(func, a, b, c, d, e, f, g)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g], function() {
		return A7(func, a, b, c, d, e, f, g);
	});
});

var _VirtualDom_lazy8 = F9(function(func, a, b, c, d, e, f, g, h)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g, h], function() {
		return A8(func, a, b, c, d, e, f, g, h);
	});
});



// FACTS


var _VirtualDom_on = F2(function(key, handler)
{
	return {
		$: 'a0',
		n: key,
		o: handler
	};
});
var _VirtualDom_style = F2(function(key, value)
{
	return {
		$: 'a1',
		n: key,
		o: value
	};
});
var _VirtualDom_property = F2(function(key, value)
{
	return {
		$: 'a2',
		n: key,
		o: value
	};
});
var _VirtualDom_attribute = F2(function(key, value)
{
	return {
		$: 'a3',
		n: key,
		o: value
	};
});
var _VirtualDom_attributeNS = F3(function(namespace, key, value)
{
	return {
		$: 'a4',
		n: key,
		o: { f: namespace, o: value }
	};
});



// XSS ATTACK VECTOR CHECKS
//
// For some reason, tabs can appear in href protocols and it still works.
// So '\tjava\tSCRIPT:alert("!!!")' and 'javascript:alert("!!!")' are the same
// in practice. That is why _VirtualDom_RE_js and _VirtualDom_RE_js_html look
// so freaky.
//
// Pulling the regular expressions out to the top level gives a slight speed
// boost in small benchmarks (4-10%) but hoisting values to reduce allocation
// can be unpredictable in large programs where JIT may have a harder time with
// functions are not fully self-contained. The benefit is more that the js and
// js_html ones are so weird that I prefer to see them near each other.


var _VirtualDom_RE_script = /^script$/i;
var _VirtualDom_RE_on_formAction = /^(on|formAction$)/i;
var _VirtualDom_RE_js = /^\s*j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:/i;
var _VirtualDom_RE_js_html = /^\s*(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:|d\s*a\s*t\s*a\s*:\s*t\s*e\s*x\s*t\s*\/\s*h\s*t\s*m\s*l\s*(,|;))/i;


function _VirtualDom_noScript(tag)
{
	return _VirtualDom_RE_script.test(tag) ? 'p' : tag;
}

function _VirtualDom_noOnOrFormAction(key)
{
	return _VirtualDom_RE_on_formAction.test(key) ? 'data-' + key : key;
}

function _VirtualDom_noInnerHtmlOrFormAction(key)
{
	return key == 'innerHTML' || key == 'outerHTML' || key == 'formAction' ? 'data-' + key : key;
}

function _VirtualDom_noJavaScriptUri(value)
{
	return _VirtualDom_RE_js.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlUri(value)
{
	return _VirtualDom_RE_js_html.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlJson(value)
{
	return (
		(typeof _Json_unwrap(value) === 'string' && _VirtualDom_RE_js_html.test(_Json_unwrap(value)))
		||
		(Array.isArray(_Json_unwrap(value)) && _VirtualDom_RE_js_html.test(String(_Json_unwrap(value))))
	)
		? _Json_wrap(
			/**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		) : value;
}



// MAP FACTS


var _VirtualDom_mapAttribute = F2(function(func, attr)
{
	return (attr.$ === 'a0')
		? A2(_VirtualDom_on, attr.n, _VirtualDom_mapHandler(func, attr.o))
		: attr;
});

function _VirtualDom_mapHandler(func, handler)
{
	var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

	// 0 = Normal
	// 1 = MayStopPropagation
	// 2 = MayPreventDefault
	// 3 = Custom

	return {
		$: handler.$,
		a:
			!tag
				? A2($elm$json$Json$Decode$map, func, handler.a)
				:
			A3($elm$json$Json$Decode$map2,
				tag < 3
					? _VirtualDom_mapEventTuple
					: _VirtualDom_mapEventRecord,
				$elm$json$Json$Decode$succeed(func),
				handler.a
			)
	};
}

var _VirtualDom_mapEventTuple = F2(function(func, tuple)
{
	return _Utils_Tuple2(func(tuple.a), tuple.b);
});

var _VirtualDom_mapEventRecord = F2(function(func, record)
{
	return {
		H: func(record.H),
		bq: record.bq,
		bk: record.bk
	}
});



// ORGANIZE FACTS


function _VirtualDom_organizeFacts(factList)
{
	for (var facts = {}; factList.b; factList = factList.b) // WHILE_CONS
	{
		var entry = factList.a;

		var tag = entry.$;
		var key = entry.n;
		var value = entry.o;

		if (tag === 'a2')
		{
			(key === 'className')
				? _VirtualDom_addClass(facts, key, _Json_unwrap(value))
				: facts[key] = _Json_unwrap(value);

			continue;
		}

		var subFacts = facts[tag] || (facts[tag] = {});
		(tag === 'a3' && key === 'class')
			? _VirtualDom_addClass(subFacts, key, value)
			: subFacts[key] = value;
	}

	return facts;
}

function _VirtualDom_addClass(object, key, newClass)
{
	var classes = object[key];
	object[key] = classes ? classes + ' ' + newClass : newClass;
}



// RENDER


function _VirtualDom_render(vNode, eventNode)
{
	var tag = vNode.$;

	if (tag === 5)
	{
		return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
	}

	if (tag === 0)
	{
		return _VirtualDom_doc.createTextNode(vNode.a);
	}

	if (tag === 4)
	{
		var subNode = vNode.k;
		var tagger = vNode.j;

		while (subNode.$ === 4)
		{
			typeof tagger !== 'object'
				? tagger = [tagger, subNode.j]
				: tagger.push(subNode.j);

			subNode = subNode.k;
		}

		var subEventRoot = { j: tagger, p: eventNode };
		var domNode = _VirtualDom_render(subNode, subEventRoot);
		domNode.elm_event_node_ref = subEventRoot;
		return domNode;
	}

	if (tag === 3)
	{
		var domNode = vNode.h(vNode.g);
		_VirtualDom_applyFacts(domNode, eventNode, vNode.d);
		return domNode;
	}

	// at this point `tag` must be 1 or 2

	var domNode = vNode.f
		? _VirtualDom_doc.createElementNS(vNode.f, vNode.c)
		: _VirtualDom_doc.createElement(vNode.c);

	if (_VirtualDom_divertHrefToApp && vNode.c == 'a')
	{
		domNode.addEventListener('click', _VirtualDom_divertHrefToApp(domNode));
	}

	_VirtualDom_applyFacts(domNode, eventNode, vNode.d);

	for (var kids = vNode.e, i = 0; i < kids.length; i++)
	{
		_VirtualDom_appendChild(domNode, _VirtualDom_render(tag === 1 ? kids[i] : kids[i].b, eventNode));
	}

	return domNode;
}



// APPLY FACTS


function _VirtualDom_applyFacts(domNode, eventNode, facts)
{
	for (var key in facts)
	{
		var value = facts[key];

		key === 'a1'
			? _VirtualDom_applyStyles(domNode, value)
			:
		key === 'a0'
			? _VirtualDom_applyEvents(domNode, eventNode, value)
			:
		key === 'a3'
			? _VirtualDom_applyAttrs(domNode, value)
			:
		key === 'a4'
			? _VirtualDom_applyAttrsNS(domNode, value)
			:
		((key !== 'value' && key !== 'checked') || domNode[key] !== value) && (domNode[key] = value);
	}
}



// APPLY STYLES


function _VirtualDom_applyStyles(domNode, styles)
{
	var domNodeStyle = domNode.style;

	for (var key in styles)
	{
		domNodeStyle[key] = styles[key];
	}
}



// APPLY ATTRS


function _VirtualDom_applyAttrs(domNode, attrs)
{
	for (var key in attrs)
	{
		var value = attrs[key];
		typeof value !== 'undefined'
			? domNode.setAttribute(key, value)
			: domNode.removeAttribute(key);
	}
}



// APPLY NAMESPACED ATTRS


function _VirtualDom_applyAttrsNS(domNode, nsAttrs)
{
	for (var key in nsAttrs)
	{
		var pair = nsAttrs[key];
		var namespace = pair.f;
		var value = pair.o;

		typeof value !== 'undefined'
			? domNode.setAttributeNS(namespace, key, value)
			: domNode.removeAttributeNS(namespace, key);
	}
}



// APPLY EVENTS


function _VirtualDom_applyEvents(domNode, eventNode, events)
{
	var allCallbacks = domNode.elmFs || (domNode.elmFs = {});

	for (var key in events)
	{
		var newHandler = events[key];
		var oldCallback = allCallbacks[key];

		if (!newHandler)
		{
			domNode.removeEventListener(key, oldCallback);
			allCallbacks[key] = undefined;
			continue;
		}

		if (oldCallback)
		{
			var oldHandler = oldCallback.q;
			if (oldHandler.$ === newHandler.$)
			{
				oldCallback.q = newHandler;
				continue;
			}
			domNode.removeEventListener(key, oldCallback);
		}

		oldCallback = _VirtualDom_makeCallback(eventNode, newHandler);
		domNode.addEventListener(key, oldCallback,
			_VirtualDom_passiveSupported
			&& { passive: $elm$virtual_dom$VirtualDom$toHandlerInt(newHandler) < 2 }
		);
		allCallbacks[key] = oldCallback;
	}
}



// PASSIVE EVENTS


var _VirtualDom_passiveSupported;

try
{
	window.addEventListener('t', null, Object.defineProperty({}, 'passive', {
		get: function() { _VirtualDom_passiveSupported = true; }
	}));
}
catch(e) {}



// EVENT HANDLERS


function _VirtualDom_makeCallback(eventNode, initialHandler)
{
	function callback(event)
	{
		var handler = callback.q;
		var result = _Json_runHelp(handler.a, event);

		if (!$elm$core$Result$isOk(result))
		{
			return;
		}

		var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

		// 0 = Normal
		// 1 = MayStopPropagation
		// 2 = MayPreventDefault
		// 3 = Custom

		var value = result.a;
		var message = !tag ? value : tag < 3 ? value.a : value.H;
		var stopPropagation = tag == 1 ? value.b : tag == 3 && value.bq;
		var currentEventNode = (
			stopPropagation && event.stopPropagation(),
			(tag == 2 ? value.b : tag == 3 && value.bk) && event.preventDefault(),
			eventNode
		);
		var tagger;
		var i;
		while (tagger = currentEventNode.j)
		{
			if (typeof tagger == 'function')
			{
				message = tagger(message);
			}
			else
			{
				for (var i = tagger.length; i--; )
				{
					message = tagger[i](message);
				}
			}
			currentEventNode = currentEventNode.p;
		}
		currentEventNode(message, stopPropagation); // stopPropagation implies isSync
	}

	callback.q = initialHandler;

	return callback;
}

function _VirtualDom_equalEvents(x, y)
{
	return x.$ == y.$ && _Json_equality(x.a, y.a);
}



// DIFF


// TODO: Should we do patches like in iOS?
//
// type Patch
//   = At Int Patch
//   | Batch (List Patch)
//   | Change ...
//
// How could it not be better?
//
function _VirtualDom_diff(x, y)
{
	var patches = [];
	_VirtualDom_diffHelp(x, y, patches, 0);
	return patches;
}


function _VirtualDom_pushPatch(patches, type, index, data)
{
	var patch = {
		$: type,
		r: index,
		s: data,
		t: undefined,
		u: undefined
	};
	patches.push(patch);
	return patch;
}


function _VirtualDom_diffHelp(x, y, patches, index)
{
	if (x === y)
	{
		return;
	}

	var xType = x.$;
	var yType = y.$;

	// Bail if you run into different types of nodes. Implies that the
	// structure has changed significantly and it's not worth a diff.
	if (xType !== yType)
	{
		if (xType === 1 && yType === 2)
		{
			y = _VirtualDom_dekey(y);
			yType = 1;
		}
		else
		{
			_VirtualDom_pushPatch(patches, 0, index, y);
			return;
		}
	}

	// Now we know that both nodes are the same $.
	switch (yType)
	{
		case 5:
			var xRefs = x.l;
			var yRefs = y.l;
			var i = xRefs.length;
			var same = i === yRefs.length;
			while (same && i--)
			{
				same = xRefs[i] === yRefs[i];
			}
			if (same)
			{
				y.k = x.k;
				return;
			}
			y.k = y.m();
			var subPatches = [];
			_VirtualDom_diffHelp(x.k, y.k, subPatches, 0);
			subPatches.length > 0 && _VirtualDom_pushPatch(patches, 1, index, subPatches);
			return;

		case 4:
			// gather nested taggers
			var xTaggers = x.j;
			var yTaggers = y.j;
			var nesting = false;

			var xSubNode = x.k;
			while (xSubNode.$ === 4)
			{
				nesting = true;

				typeof xTaggers !== 'object'
					? xTaggers = [xTaggers, xSubNode.j]
					: xTaggers.push(xSubNode.j);

				xSubNode = xSubNode.k;
			}

			var ySubNode = y.k;
			while (ySubNode.$ === 4)
			{
				nesting = true;

				typeof yTaggers !== 'object'
					? yTaggers = [yTaggers, ySubNode.j]
					: yTaggers.push(ySubNode.j);

				ySubNode = ySubNode.k;
			}

			// Just bail if different numbers of taggers. This implies the
			// structure of the virtual DOM has changed.
			if (nesting && xTaggers.length !== yTaggers.length)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			// check if taggers are "the same"
			if (nesting ? !_VirtualDom_pairwiseRefEqual(xTaggers, yTaggers) : xTaggers !== yTaggers)
			{
				_VirtualDom_pushPatch(patches, 2, index, yTaggers);
			}

			// diff everything below the taggers
			_VirtualDom_diffHelp(xSubNode, ySubNode, patches, index + 1);
			return;

		case 0:
			if (x.a !== y.a)
			{
				_VirtualDom_pushPatch(patches, 3, index, y.a);
			}
			return;

		case 1:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKids);
			return;

		case 2:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKeyedKids);
			return;

		case 3:
			if (x.h !== y.h)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
			factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

			var patch = y.i(x.g, y.g);
			patch && _VirtualDom_pushPatch(patches, 5, index, patch);

			return;
	}
}

// assumes the incoming arrays are the same length
function _VirtualDom_pairwiseRefEqual(as, bs)
{
	for (var i = 0; i < as.length; i++)
	{
		if (as[i] !== bs[i])
		{
			return false;
		}
	}

	return true;
}

function _VirtualDom_diffNodes(x, y, patches, index, diffKids)
{
	// Bail if obvious indicators have changed. Implies more serious
	// structural changes such that it's not worth it to diff.
	if (x.c !== y.c || x.f !== y.f)
	{
		_VirtualDom_pushPatch(patches, 0, index, y);
		return;
	}

	var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
	factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

	diffKids(x, y, patches, index);
}



// DIFF FACTS


// TODO Instead of creating a new diff object, it's possible to just test if
// there *is* a diff. During the actual patch, do the diff again and make the
// modifications directly. This way, there's no new allocations. Worth it?
function _VirtualDom_diffFacts(x, y, category)
{
	var diff;

	// look for changes and removals
	for (var xKey in x)
	{
		if (xKey === 'a1' || xKey === 'a0' || xKey === 'a3' || xKey === 'a4')
		{
			var subDiff = _VirtualDom_diffFacts(x[xKey], y[xKey] || {}, xKey);
			if (subDiff)
			{
				diff = diff || {};
				diff[xKey] = subDiff;
			}
			continue;
		}

		// remove if not in the new facts
		if (!(xKey in y))
		{
			diff = diff || {};
			diff[xKey] =
				!category
					? (typeof x[xKey] === 'string' ? '' : null)
					:
				(category === 'a1')
					? ''
					:
				(category === 'a0' || category === 'a3')
					? undefined
					:
				{ f: x[xKey].f, o: undefined };

			continue;
		}

		var xValue = x[xKey];
		var yValue = y[xKey];

		// reference equal, so don't worry about it
		if (xValue === yValue && xKey !== 'value' && xKey !== 'checked'
			|| category === 'a0' && _VirtualDom_equalEvents(xValue, yValue))
		{
			continue;
		}

		diff = diff || {};
		diff[xKey] = yValue;
	}

	// add new stuff
	for (var yKey in y)
	{
		if (!(yKey in x))
		{
			diff = diff || {};
			diff[yKey] = y[yKey];
		}
	}

	return diff;
}



// DIFF KIDS


function _VirtualDom_diffKids(xParent, yParent, patches, index)
{
	var xKids = xParent.e;
	var yKids = yParent.e;

	var xLen = xKids.length;
	var yLen = yKids.length;

	// FIGURE OUT IF THERE ARE INSERTS OR REMOVALS

	if (xLen > yLen)
	{
		_VirtualDom_pushPatch(patches, 6, index, {
			v: yLen,
			i: xLen - yLen
		});
	}
	else if (xLen < yLen)
	{
		_VirtualDom_pushPatch(patches, 7, index, {
			v: xLen,
			e: yKids
		});
	}

	// PAIRWISE DIFF EVERYTHING ELSE

	for (var minLen = xLen < yLen ? xLen : yLen, i = 0; i < minLen; i++)
	{
		var xKid = xKids[i];
		_VirtualDom_diffHelp(xKid, yKids[i], patches, ++index);
		index += xKid.b || 0;
	}
}



// KEYED DIFF


function _VirtualDom_diffKeyedKids(xParent, yParent, patches, rootIndex)
{
	var localPatches = [];

	var changes = {}; // Dict String Entry
	var inserts = []; // Array { index : Int, entry : Entry }
	// type Entry = { tag : String, vnode : VNode, index : Int, data : _ }

	var xKids = xParent.e;
	var yKids = yParent.e;
	var xLen = xKids.length;
	var yLen = yKids.length;
	var xIndex = 0;
	var yIndex = 0;

	var index = rootIndex;

	while (xIndex < xLen && yIndex < yLen)
	{
		var x = xKids[xIndex];
		var y = yKids[yIndex];

		var xKey = x.a;
		var yKey = y.a;
		var xNode = x.b;
		var yNode = y.b;

		var newMatch = undefined;
		var oldMatch = undefined;

		// check if keys match

		if (xKey === yKey)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNode, localPatches, index);
			index += xNode.b || 0;

			xIndex++;
			yIndex++;
			continue;
		}

		// look ahead 1 to detect insertions and removals.

		var xNext = xKids[xIndex + 1];
		var yNext = yKids[yIndex + 1];

		if (xNext)
		{
			var xNextKey = xNext.a;
			var xNextNode = xNext.b;
			oldMatch = yKey === xNextKey;
		}

		if (yNext)
		{
			var yNextKey = yNext.a;
			var yNextNode = yNext.b;
			newMatch = xKey === yNextKey;
		}


		// swap x and y
		if (newMatch && oldMatch)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			_VirtualDom_insertNode(changes, localPatches, xKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNextNode, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		// insert y
		if (newMatch)
		{
			index++;
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			index += xNode.b || 0;

			xIndex += 1;
			yIndex += 2;
			continue;
		}

		// remove x
		if (oldMatch)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 1;
			continue;
		}

		// remove x, insert y
		if (xNext && xNextKey === yNextKey)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNextNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		break;
	}

	// eat up any remaining nodes with removeNode and insertNode

	while (xIndex < xLen)
	{
		index++;
		var x = xKids[xIndex];
		var xNode = x.b;
		_VirtualDom_removeNode(changes, localPatches, x.a, xNode, index);
		index += xNode.b || 0;
		xIndex++;
	}

	while (yIndex < yLen)
	{
		var endInserts = endInserts || [];
		var y = yKids[yIndex];
		_VirtualDom_insertNode(changes, localPatches, y.a, y.b, undefined, endInserts);
		yIndex++;
	}

	if (localPatches.length > 0 || inserts.length > 0 || endInserts)
	{
		_VirtualDom_pushPatch(patches, 8, rootIndex, {
			w: localPatches,
			x: inserts,
			y: endInserts
		});
	}
}



// CHANGES FROM KEYED DIFF


var _VirtualDom_POSTFIX = '_elmW6BL';


function _VirtualDom_insertNode(changes, localPatches, key, vnode, yIndex, inserts)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		entry = {
			c: 0,
			z: vnode,
			r: yIndex,
			s: undefined
		};

		inserts.push({ r: yIndex, A: entry });
		changes[key] = entry;

		return;
	}

	// this key was removed earlier, a match!
	if (entry.c === 1)
	{
		inserts.push({ r: yIndex, A: entry });

		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(entry.z, vnode, subPatches, entry.r);
		entry.r = yIndex;
		entry.s.s = {
			w: subPatches,
			A: entry
		};

		return;
	}

	// this key has already been inserted or moved, a duplicate!
	_VirtualDom_insertNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, yIndex, inserts);
}


function _VirtualDom_removeNode(changes, localPatches, key, vnode, index)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		var patch = _VirtualDom_pushPatch(localPatches, 9, index, undefined);

		changes[key] = {
			c: 1,
			z: vnode,
			r: index,
			s: patch
		};

		return;
	}

	// this key was inserted earlier, a match!
	if (entry.c === 0)
	{
		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(vnode, entry.z, subPatches, index);

		_VirtualDom_pushPatch(localPatches, 9, index, {
			w: subPatches,
			A: entry
		});

		return;
	}

	// this key has already been removed or moved, a duplicate!
	_VirtualDom_removeNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, index);
}



// ADD DOM NODES
//
// Each DOM node has an "index" assigned in order of traversal. It is important
// to minimize our crawl over the actual DOM, so these indexes (along with the
// descendantsCount of virtual nodes) let us skip touching entire subtrees of
// the DOM if we know there are no patches there.


function _VirtualDom_addDomNodes(domNode, vNode, patches, eventNode)
{
	_VirtualDom_addDomNodesHelp(domNode, vNode, patches, 0, 0, vNode.b, eventNode);
}


// assumes `patches` is non-empty and indexes increase monotonically.
function _VirtualDom_addDomNodesHelp(domNode, vNode, patches, i, low, high, eventNode)
{
	var patch = patches[i];
	var index = patch.r;

	while (index === low)
	{
		var patchType = patch.$;

		if (patchType === 1)
		{
			_VirtualDom_addDomNodes(domNode, vNode.k, patch.s, eventNode);
		}
		else if (patchType === 8)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var subPatches = patch.s.w;
			if (subPatches.length > 0)
			{
				_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
			}
		}
		else if (patchType === 9)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var data = patch.s;
			if (data)
			{
				data.A.s = domNode;
				var subPatches = data.w;
				if (subPatches.length > 0)
				{
					_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
				}
			}
		}
		else
		{
			patch.t = domNode;
			patch.u = eventNode;
		}

		i++;

		if (!(patch = patches[i]) || (index = patch.r) > high)
		{
			return i;
		}
	}

	var tag = vNode.$;

	if (tag === 4)
	{
		var subNode = vNode.k;

		while (subNode.$ === 4)
		{
			subNode = subNode.k;
		}

		return _VirtualDom_addDomNodesHelp(domNode, subNode, patches, i, low + 1, high, domNode.elm_event_node_ref);
	}

	// tag must be 1 or 2 at this point

	var vKids = vNode.e;
	var childNodes = domNode.childNodes;
	for (var j = 0; j < vKids.length; j++)
	{
		low++;
		var vKid = tag === 1 ? vKids[j] : vKids[j].b;
		var nextLow = low + (vKid.b || 0);
		if (low <= index && index <= nextLow)
		{
			i = _VirtualDom_addDomNodesHelp(childNodes[j], vKid, patches, i, low, nextLow, eventNode);
			if (!(patch = patches[i]) || (index = patch.r) > high)
			{
				return i;
			}
		}
		low = nextLow;
	}
	return i;
}



// APPLY PATCHES


function _VirtualDom_applyPatches(rootDomNode, oldVirtualNode, patches, eventNode)
{
	if (patches.length === 0)
	{
		return rootDomNode;
	}

	_VirtualDom_addDomNodes(rootDomNode, oldVirtualNode, patches, eventNode);
	return _VirtualDom_applyPatchesHelp(rootDomNode, patches);
}

function _VirtualDom_applyPatchesHelp(rootDomNode, patches)
{
	for (var i = 0; i < patches.length; i++)
	{
		var patch = patches[i];
		var localDomNode = patch.t
		var newNode = _VirtualDom_applyPatch(localDomNode, patch);
		if (localDomNode === rootDomNode)
		{
			rootDomNode = newNode;
		}
	}
	return rootDomNode;
}

function _VirtualDom_applyPatch(domNode, patch)
{
	switch (patch.$)
	{
		case 0:
			return _VirtualDom_applyPatchRedraw(domNode, patch.s, patch.u);

		case 4:
			_VirtualDom_applyFacts(domNode, patch.u, patch.s);
			return domNode;

		case 3:
			domNode.replaceData(0, domNode.length, patch.s);
			return domNode;

		case 1:
			return _VirtualDom_applyPatchesHelp(domNode, patch.s);

		case 2:
			if (domNode.elm_event_node_ref)
			{
				domNode.elm_event_node_ref.j = patch.s;
			}
			else
			{
				domNode.elm_event_node_ref = { j: patch.s, p: patch.u };
			}
			return domNode;

		case 6:
			var data = patch.s;
			for (var i = 0; i < data.i; i++)
			{
				domNode.removeChild(domNode.childNodes[data.v]);
			}
			return domNode;

		case 7:
			var data = patch.s;
			var kids = data.e;
			var i = data.v;
			var theEnd = domNode.childNodes[i];
			for (; i < kids.length; i++)
			{
				domNode.insertBefore(_VirtualDom_render(kids[i], patch.u), theEnd);
			}
			return domNode;

		case 9:
			var data = patch.s;
			if (!data)
			{
				domNode.parentNode.removeChild(domNode);
				return domNode;
			}
			var entry = data.A;
			if (typeof entry.r !== 'undefined')
			{
				domNode.parentNode.removeChild(domNode);
			}
			entry.s = _VirtualDom_applyPatchesHelp(domNode, data.w);
			return domNode;

		case 8:
			return _VirtualDom_applyPatchReorder(domNode, patch);

		case 5:
			return patch.s(domNode);

		default:
			_Debug_crash(10); // 'Ran into an unknown patch!'
	}
}


function _VirtualDom_applyPatchRedraw(domNode, vNode, eventNode)
{
	var parentNode = domNode.parentNode;
	var newNode = _VirtualDom_render(vNode, eventNode);

	if (!newNode.elm_event_node_ref)
	{
		newNode.elm_event_node_ref = domNode.elm_event_node_ref;
	}

	if (parentNode && newNode !== domNode)
	{
		parentNode.replaceChild(newNode, domNode);
	}
	return newNode;
}


function _VirtualDom_applyPatchReorder(domNode, patch)
{
	var data = patch.s;

	// remove end inserts
	var frag = _VirtualDom_applyPatchReorderEndInsertsHelp(data.y, patch);

	// removals
	domNode = _VirtualDom_applyPatchesHelp(domNode, data.w);

	// inserts
	var inserts = data.x;
	for (var i = 0; i < inserts.length; i++)
	{
		var insert = inserts[i];
		var entry = insert.A;
		var node = entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u);
		domNode.insertBefore(node, domNode.childNodes[insert.r]);
	}

	// add end inserts
	if (frag)
	{
		_VirtualDom_appendChild(domNode, frag);
	}

	return domNode;
}


function _VirtualDom_applyPatchReorderEndInsertsHelp(endInserts, patch)
{
	if (!endInserts)
	{
		return;
	}

	var frag = _VirtualDom_doc.createDocumentFragment();
	for (var i = 0; i < endInserts.length; i++)
	{
		var insert = endInserts[i];
		var entry = insert.A;
		_VirtualDom_appendChild(frag, entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u)
		);
	}
	return frag;
}


function _VirtualDom_virtualize(node)
{
	// TEXT NODES

	if (node.nodeType === 3)
	{
		return _VirtualDom_text(node.textContent);
	}


	// WEIRD NODES

	if (node.nodeType !== 1)
	{
		return _VirtualDom_text('');
	}


	// ELEMENT NODES

	var attrList = _List_Nil;
	var attrs = node.attributes;
	for (var i = attrs.length; i--; )
	{
		var attr = attrs[i];
		var name = attr.name;
		var value = attr.value;
		attrList = _List_Cons( A2(_VirtualDom_attribute, name, value), attrList );
	}

	var tag = node.tagName.toLowerCase();
	var kidList = _List_Nil;
	var kids = node.childNodes;

	for (var i = kids.length; i--; )
	{
		kidList = _List_Cons(_VirtualDom_virtualize(kids[i]), kidList);
	}
	return A3(_VirtualDom_node, tag, attrList, kidList);
}

function _VirtualDom_dekey(keyedNode)
{
	var keyedKids = keyedNode.e;
	var len = keyedKids.length;
	var kids = new Array(len);
	for (var i = 0; i < len; i++)
	{
		kids[i] = keyedKids[i].b;
	}

	return {
		$: 1,
		c: keyedNode.c,
		d: keyedNode.d,
		e: kids,
		f: keyedNode.f,
		b: keyedNode.b
	};
}




// ELEMENT


var _Debugger_element;

var _Browser_element = _Debugger_element || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.cY,
		impl.dy,
		impl.dt,
		function(sendToApp, initialModel) {
			var view = impl.dB;
			/**/
			var domNode = args['node'];
			//*/
			/**_UNUSED/
			var domNode = args && args['node'] ? args['node'] : _Debug_crash(0);
			//*/
			var currNode = _VirtualDom_virtualize(domNode);

			return _Browser_makeAnimator(initialModel, function(model)
			{
				var nextNode = view(model);
				var patches = _VirtualDom_diff(currNode, nextNode);
				domNode = _VirtualDom_applyPatches(domNode, currNode, patches, sendToApp);
				currNode = nextNode;
			});
		}
	);
});



// DOCUMENT


var _Debugger_document;

var _Browser_document = _Debugger_document || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.cY,
		impl.dy,
		impl.dt,
		function(sendToApp, initialModel) {
			var divertHrefToApp = impl.bm && impl.bm(sendToApp)
			var view = impl.dB;
			var title = _VirtualDom_doc.title;
			var bodyNode = _VirtualDom_doc.body;
			var currNode = _VirtualDom_virtualize(bodyNode);
			return _Browser_makeAnimator(initialModel, function(model)
			{
				_VirtualDom_divertHrefToApp = divertHrefToApp;
				var doc = view(model);
				var nextNode = _VirtualDom_node('body')(_List_Nil)(doc.aE);
				var patches = _VirtualDom_diff(currNode, nextNode);
				bodyNode = _VirtualDom_applyPatches(bodyNode, currNode, patches, sendToApp);
				currNode = nextNode;
				_VirtualDom_divertHrefToApp = 0;
				(title !== doc.ay) && (_VirtualDom_doc.title = title = doc.ay);
			});
		}
	);
});



// ANIMATION


var _Browser_cancelAnimationFrame =
	typeof cancelAnimationFrame !== 'undefined'
		? cancelAnimationFrame
		: function(id) { clearTimeout(id); };

var _Browser_requestAnimationFrame =
	typeof requestAnimationFrame !== 'undefined'
		? requestAnimationFrame
		: function(callback) { return setTimeout(callback, 1000 / 60); };


function _Browser_makeAnimator(model, draw)
{
	draw(model);

	var state = 0;

	function updateIfNeeded()
	{
		state = state === 1
			? 0
			: ( _Browser_requestAnimationFrame(updateIfNeeded), draw(model), 1 );
	}

	return function(nextModel, isSync)
	{
		model = nextModel;

		isSync
			? ( draw(model),
				state === 2 && (state = 1)
				)
			: ( state === 0 && _Browser_requestAnimationFrame(updateIfNeeded),
				state = 2
				);
	};
}



// APPLICATION


function _Browser_application(impl)
{
	var onUrlChange = impl.c2;
	var onUrlRequest = impl.c3;
	var key = function() { key.a(onUrlChange(_Browser_getUrl())); };

	return _Browser_document({
		bm: function(sendToApp)
		{
			key.a = sendToApp;
			_Browser_window.addEventListener('popstate', key);
			_Browser_window.navigator.userAgent.indexOf('Trident') < 0 || _Browser_window.addEventListener('hashchange', key);

			return F2(function(domNode, event)
			{
				if (!event.ctrlKey && !event.metaKey && !event.shiftKey && event.button < 1 && !domNode.target && !domNode.hasAttribute('download'))
				{
					event.preventDefault();
					var href = domNode.href;
					var curr = _Browser_getUrl();
					var next = $elm$url$Url$fromString(href).a;
					sendToApp(onUrlRequest(
						(next
							&& curr.b3 === next.b3
							&& curr.bN === next.bN
							&& curr.b$.a === next.b$.a
						)
							? $elm$browser$Browser$Internal(next)
							: $elm$browser$Browser$External(href)
					));
				}
			});
		},
		cY: function(flags)
		{
			return A3(impl.cY, flags, _Browser_getUrl(), key);
		},
		dB: impl.dB,
		dy: impl.dy,
		dt: impl.dt
	});
}

function _Browser_getUrl()
{
	return $elm$url$Url$fromString(_VirtualDom_doc.location.href).a || _Debug_crash(1);
}

var _Browser_go = F2(function(key, n)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		n && history.go(n);
		key();
	}));
});

var _Browser_pushUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.pushState({}, '', url);
		key();
	}));
});

var _Browser_replaceUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.replaceState({}, '', url);
		key();
	}));
});



// GLOBAL EVENTS


var _Browser_fakeNode = { addEventListener: function() {}, removeEventListener: function() {} };
var _Browser_doc = typeof document !== 'undefined' ? document : _Browser_fakeNode;
var _Browser_window = typeof window !== 'undefined' ? window : _Browser_fakeNode;

var _Browser_on = F3(function(node, eventName, sendToSelf)
{
	return _Scheduler_spawn(_Scheduler_binding(function(callback)
	{
		function handler(event)	{ _Scheduler_rawSpawn(sendToSelf(event)); }
		node.addEventListener(eventName, handler, _VirtualDom_passiveSupported && { passive: true });
		return function() { node.removeEventListener(eventName, handler); };
	}));
});

var _Browser_decodeEvent = F2(function(decoder, event)
{
	var result = _Json_runHelp(decoder, event);
	return $elm$core$Result$isOk(result) ? $elm$core$Maybe$Just(result.a) : $elm$core$Maybe$Nothing;
});



// PAGE VISIBILITY


function _Browser_visibilityInfo()
{
	return (typeof _VirtualDom_doc.hidden !== 'undefined')
		? { cV: 'hidden', cz: 'visibilitychange' }
		:
	(typeof _VirtualDom_doc.mozHidden !== 'undefined')
		? { cV: 'mozHidden', cz: 'mozvisibilitychange' }
		:
	(typeof _VirtualDom_doc.msHidden !== 'undefined')
		? { cV: 'msHidden', cz: 'msvisibilitychange' }
		:
	(typeof _VirtualDom_doc.webkitHidden !== 'undefined')
		? { cV: 'webkitHidden', cz: 'webkitvisibilitychange' }
		: { cV: 'hidden', cz: 'visibilitychange' };
}



// ANIMATION FRAMES


function _Browser_rAF()
{
	return _Scheduler_binding(function(callback)
	{
		var id = _Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(Date.now()));
		});

		return function() {
			_Browser_cancelAnimationFrame(id);
		};
	});
}


function _Browser_now()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(Date.now()));
	});
}



// DOM STUFF


function _Browser_withNode(id, doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			var node = document.getElementById(id);
			callback(node
				? _Scheduler_succeed(doStuff(node))
				: _Scheduler_fail($elm$browser$Browser$Dom$NotFound(id))
			);
		});
	});
}


function _Browser_withWindow(doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(doStuff()));
		});
	});
}


// FOCUS and BLUR


var _Browser_call = F2(function(functionName, id)
{
	return _Browser_withNode(id, function(node) {
		node[functionName]();
		return _Utils_Tuple0;
	});
});



// WINDOW VIEWPORT


function _Browser_getViewport()
{
	return {
		b9: _Browser_getScene(),
		ci: {
			cm: _Browser_window.pageXOffset,
			cn: _Browser_window.pageYOffset,
			cl: _Browser_doc.documentElement.clientWidth,
			bL: _Browser_doc.documentElement.clientHeight
		}
	};
}

function _Browser_getScene()
{
	var body = _Browser_doc.body;
	var elem = _Browser_doc.documentElement;
	return {
		cl: Math.max(body.scrollWidth, body.offsetWidth, elem.scrollWidth, elem.offsetWidth, elem.clientWidth),
		bL: Math.max(body.scrollHeight, body.offsetHeight, elem.scrollHeight, elem.offsetHeight, elem.clientHeight)
	};
}

var _Browser_setViewport = F2(function(x, y)
{
	return _Browser_withWindow(function()
	{
		_Browser_window.scroll(x, y);
		return _Utils_Tuple0;
	});
});



// ELEMENT VIEWPORT


function _Browser_getViewportOf(id)
{
	return _Browser_withNode(id, function(node)
	{
		return {
			b9: {
				cl: node.scrollWidth,
				bL: node.scrollHeight
			},
			ci: {
				cm: node.scrollLeft,
				cn: node.scrollTop,
				cl: node.clientWidth,
				bL: node.clientHeight
			}
		};
	});
}


var _Browser_setViewportOf = F3(function(id, x, y)
{
	return _Browser_withNode(id, function(node)
	{
		node.scrollLeft = x;
		node.scrollTop = y;
		return _Utils_Tuple0;
	});
});



// ELEMENT


function _Browser_getElement(id)
{
	return _Browser_withNode(id, function(node)
	{
		var rect = node.getBoundingClientRect();
		var x = _Browser_window.pageXOffset;
		var y = _Browser_window.pageYOffset;
		return {
			b9: _Browser_getScene(),
			ci: {
				cm: x,
				cn: y,
				cl: _Browser_doc.documentElement.clientWidth,
				bL: _Browser_doc.documentElement.clientHeight
			},
			cK: {
				cm: x + rect.left,
				cn: y + rect.top,
				cl: rect.width,
				bL: rect.height
			}
		};
	});
}



// LOAD and RELOAD


function _Browser_reload(skipCache)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		_VirtualDom_doc.location.reload(skipCache);
	}));
}

function _Browser_load(url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		try
		{
			_Browser_window.location = url;
		}
		catch(err)
		{
			// Only Firefox can throw a NS_ERROR_MALFORMED_URI exception here.
			// Other browsers reload the page, so let's be consistent about that.
			_VirtualDom_doc.location.reload(false);
		}
	}));
}


function _Url_percentEncode(string)
{
	return encodeURIComponent(string);
}

function _Url_percentDecode(string)
{
	try
	{
		return $elm$core$Maybe$Just(decodeURIComponent(string));
	}
	catch (e)
	{
		return $elm$core$Maybe$Nothing;
	}
}


function _Time_now(millisToPosix)
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(millisToPosix(Date.now())));
	});
}

var _Time_setInterval = F2(function(interval, task)
{
	return _Scheduler_binding(function(callback)
	{
		var id = setInterval(function() { _Scheduler_rawSpawn(task); }, interval);
		return function() { clearInterval(id); };
	});
});

function _Time_here()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(
			A2($elm$time$Time$customZone, -(new Date().getTimezoneOffset()), _List_Nil)
		));
	});
}


function _Time_getZoneName()
{
	return _Scheduler_binding(function(callback)
	{
		try
		{
			var name = $elm$time$Time$Name(Intl.DateTimeFormat().resolvedOptions().timeZone);
		}
		catch (e)
		{
			var name = $elm$time$Time$Offset(new Date().getTimezoneOffset());
		}
		callback(_Scheduler_succeed(name));
	});
}



// SEND REQUEST

var _Http_toTask = F3(function(router, toTask, request)
{
	return _Scheduler_binding(function(callback)
	{
		function done(response) {
			callback(toTask(request.aL.a(response)));
		}

		var xhr = new XMLHttpRequest();
		xhr.addEventListener('error', function() { done($elm$http$Http$NetworkError_); });
		xhr.addEventListener('timeout', function() { done($elm$http$Http$Timeout_); });
		xhr.addEventListener('load', function() { done(_Http_toResponse(request.aL.b, xhr)); });
		$elm$core$Maybe$isJust(request.bs) && _Http_track(router, xhr, request.bs.a);

		try {
			xhr.open(request.be, request.a_, true);
		} catch (e) {
			return done($elm$http$Http$BadUrl_(request.a_));
		}

		_Http_configureRequest(xhr, request);

		request.aE.a && xhr.setRequestHeader('Content-Type', request.aE.a);
		xhr.send(request.aE.b);

		return function() { xhr.c = true; xhr.abort(); };
	});
});


// CONFIGURE

function _Http_configureRequest(xhr, request)
{
	for (var headers = request.a8; headers.b; headers = headers.b) // WHILE_CONS
	{
		xhr.setRequestHeader(headers.a.a, headers.a.b);
	}
	xhr.timeout = request.br.a || 0;
	xhr.responseType = request.aL.d;
	xhr.withCredentials = request.cr;
}


// RESPONSES

function _Http_toResponse(toBody, xhr)
{
	return A2(
		200 <= xhr.status && xhr.status < 300 ? $elm$http$Http$GoodStatus_ : $elm$http$Http$BadStatus_,
		_Http_toMetadata(xhr),
		toBody(xhr.response)
	);
}


// METADATA

function _Http_toMetadata(xhr)
{
	return {
		a_: xhr.responseURL,
		av: xhr.status,
		ds: xhr.statusText,
		a8: _Http_parseHeaders(xhr.getAllResponseHeaders())
	};
}


// HEADERS

function _Http_parseHeaders(rawHeaders)
{
	if (!rawHeaders)
	{
		return $elm$core$Dict$empty;
	}

	var headers = $elm$core$Dict$empty;
	var headerPairs = rawHeaders.split('\r\n');
	for (var i = headerPairs.length; i--; )
	{
		var headerPair = headerPairs[i];
		var index = headerPair.indexOf(': ');
		if (index > 0)
		{
			var key = headerPair.substring(0, index);
			var value = headerPair.substring(index + 2);

			headers = A3($elm$core$Dict$update, key, function(oldValue) {
				return $elm$core$Maybe$Just($elm$core$Maybe$isJust(oldValue)
					? value + ', ' + oldValue.a
					: value
				);
			}, headers);
		}
	}
	return headers;
}


// EXPECT

var _Http_expect = F3(function(type, toBody, toValue)
{
	return {
		$: 0,
		d: type,
		b: toBody,
		a: toValue
	};
});

var _Http_mapExpect = F2(function(func, expect)
{
	return {
		$: 0,
		d: expect.d,
		b: expect.b,
		a: function(x) { return func(expect.a(x)); }
	};
});

function _Http_toDataView(arrayBuffer)
{
	return new DataView(arrayBuffer);
}


// BODY and PARTS

var _Http_emptyBody = { $: 0 };
var _Http_pair = F2(function(a, b) { return { $: 0, a: a, b: b }; });

function _Http_toFormData(parts)
{
	for (var formData = new FormData(); parts.b; parts = parts.b) // WHILE_CONS
	{
		var part = parts.a;
		formData.append(part.a, part.b);
	}
	return formData;
}

var _Http_bytesToBlob = F2(function(mime, bytes)
{
	return new Blob([bytes], { type: mime });
});


// PROGRESS

function _Http_track(router, xhr, tracker)
{
	// TODO check out lengthComputable on loadstart event

	xhr.upload.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Sending({
			dj: event.loaded,
			dk: event.total
		}))));
	});
	xhr.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Receiving({
			de: event.loaded,
			dk: event.lengthComputable ? $elm$core$Maybe$Just(event.total) : $elm$core$Maybe$Nothing
		}))));
	});
}


var _Bitwise_and = F2(function(a, b)
{
	return a & b;
});

var _Bitwise_or = F2(function(a, b)
{
	return a | b;
});

var _Bitwise_xor = F2(function(a, b)
{
	return a ^ b;
});

function _Bitwise_complement(a)
{
	return ~a;
};

var _Bitwise_shiftLeftBy = F2(function(offset, a)
{
	return a << offset;
});

var _Bitwise_shiftRightBy = F2(function(offset, a)
{
	return a >> offset;
});

var _Bitwise_shiftRightZfBy = F2(function(offset, a)
{
	return a >>> offset;
});




// STRINGS


var _Parser_isSubString = F5(function(smallString, offset, row, col, bigString)
{
	var smallLength = smallString.length;
	var isGood = offset + smallLength <= bigString.length;

	for (var i = 0; isGood && i < smallLength; )
	{
		var code = bigString.charCodeAt(offset);
		isGood =
			smallString[i++] === bigString[offset++]
			&& (
				code === 0x000A /* \n */
					? ( row++, col=1 )
					: ( col++, (code & 0xF800) === 0xD800 ? smallString[i++] === bigString[offset++] : 1 )
			)
	}

	return _Utils_Tuple3(isGood ? offset : -1, row, col);
});



// CHARS


var _Parser_isSubChar = F3(function(predicate, offset, string)
{
	return (
		string.length <= offset
			? -1
			:
		(string.charCodeAt(offset) & 0xF800) === 0xD800
			? (predicate(_Utils_chr(string.substr(offset, 2))) ? offset + 2 : -1)
			:
		(predicate(_Utils_chr(string[offset]))
			? ((string[offset] === '\n') ? -2 : (offset + 1))
			: -1
		)
	);
});


var _Parser_isAsciiCode = F3(function(code, offset, string)
{
	return string.charCodeAt(offset) === code;
});



// NUMBERS


var _Parser_chompBase10 = F2(function(offset, string)
{
	for (; offset < string.length; offset++)
	{
		var code = string.charCodeAt(offset);
		if (code < 0x30 || 0x39 < code)
		{
			return offset;
		}
	}
	return offset;
});


var _Parser_consumeBase = F3(function(base, offset, string)
{
	for (var total = 0; offset < string.length; offset++)
	{
		var digit = string.charCodeAt(offset) - 0x30;
		if (digit < 0 || base <= digit) break;
		total = base * total + digit;
	}
	return _Utils_Tuple2(offset, total);
});


var _Parser_consumeBase16 = F2(function(offset, string)
{
	for (var total = 0; offset < string.length; offset++)
	{
		var code = string.charCodeAt(offset);
		if (0x30 <= code && code <= 0x39)
		{
			total = 16 * total + code - 0x30;
		}
		else if (0x41 <= code && code <= 0x46)
		{
			total = 16 * total + code - 55;
		}
		else if (0x61 <= code && code <= 0x66)
		{
			total = 16 * total + code - 87;
		}
		else
		{
			break;
		}
	}
	return _Utils_Tuple2(offset, total);
});



// FIND STRING


var _Parser_findSubString = F5(function(smallString, offset, row, col, bigString)
{
	var newOffset = bigString.indexOf(smallString, offset);
	var target = newOffset < 0 ? bigString.length : newOffset + smallString.length;

	while (offset < target)
	{
		var code = bigString.charCodeAt(offset++);
		code === 0x000A /* \n */
			? ( col=1, row++ )
			: ( col++, (code & 0xF800) === 0xD800 && offset++ )
	}

	return _Utils_Tuple3(newOffset, row, col);
});



// DECODER

var _File_decoder = _Json_decodePrim(function(value) {
	// NOTE: checks if `File` exists in case this is run on node
	return (typeof File !== 'undefined' && value instanceof File)
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FILE', value);
});


// METADATA

function _File_name(file) { return file.name; }
function _File_mime(file) { return file.type; }
function _File_size(file) { return file.size; }

function _File_lastModified(file)
{
	return $elm$time$Time$millisToPosix(file.lastModified);
}


// DOWNLOAD

var _File_downloadNode;

function _File_getDownloadNode()
{
	return _File_downloadNode || (_File_downloadNode = document.createElement('a'));
}

var _File_download = F3(function(name, mime, content)
{
	return _Scheduler_binding(function(callback)
	{
		var blob = new Blob([content], {type: mime});

		// for IE10+
		if (navigator.msSaveOrOpenBlob)
		{
			navigator.msSaveOrOpenBlob(blob, name);
			return;
		}

		// for HTML5
		var node = _File_getDownloadNode();
		var objectUrl = URL.createObjectURL(blob);
		node.href = objectUrl;
		node.download = name;
		_File_click(node);
		URL.revokeObjectURL(objectUrl);
	});
});

function _File_downloadUrl(href)
{
	return _Scheduler_binding(function(callback)
	{
		var node = _File_getDownloadNode();
		node.href = href;
		node.download = '';
		node.origin === location.origin || (node.target = '_blank');
		_File_click(node);
	});
}


// IE COMPATIBILITY

function _File_makeBytesSafeForInternetExplorer(bytes)
{
	// only needed by IE10 and IE11 to fix https://github.com/elm/file/issues/10
	// all other browsers can just run `new Blob([bytes])` directly with no problem
	//
	return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

function _File_click(node)
{
	// only needed by IE10 and IE11 to fix https://github.com/elm/file/issues/11
	// all other browsers have MouseEvent and do not need this conditional stuff
	//
	if (typeof MouseEvent === 'function')
	{
		node.dispatchEvent(new MouseEvent('click'));
	}
	else
	{
		var event = document.createEvent('MouseEvents');
		event.initMouseEvent('click', true, true, window, 0, 0, 0, 0, 0, false, false, false, false, 0, null);
		document.body.appendChild(node);
		node.dispatchEvent(event);
		document.body.removeChild(node);
	}
}


// UPLOAD

var _File_node;

function _File_uploadOne(mimes)
{
	return _Scheduler_binding(function(callback)
	{
		_File_node = document.createElement('input');
		_File_node.type = 'file';
		_File_node.accept = A2($elm$core$String$join, ',', mimes);
		_File_node.addEventListener('change', function(event)
		{
			callback(_Scheduler_succeed(event.target.files[0]));
		});
		_File_click(_File_node);
	});
}

function _File_uploadOneOrMore(mimes)
{
	return _Scheduler_binding(function(callback)
	{
		_File_node = document.createElement('input');
		_File_node.type = 'file';
		_File_node.multiple = true;
		_File_node.accept = A2($elm$core$String$join, ',', mimes);
		_File_node.addEventListener('change', function(event)
		{
			var elmFiles = _List_fromArray(event.target.files);
			callback(_Scheduler_succeed(_Utils_Tuple2(elmFiles.a, elmFiles.b)));
		});
		_File_click(_File_node);
	});
}


// CONTENT

function _File_toString(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(reader.result));
		});
		reader.readAsText(blob);
		return function() { reader.abort(); };
	});
}

function _File_toBytes(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(new DataView(reader.result)));
		});
		reader.readAsArrayBuffer(blob);
		return function() { reader.abort(); };
	});
}

function _File_toUrl(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(reader.result));
		});
		reader.readAsDataURL(blob);
		return function() { reader.abort(); };
	});
}

var $author$project$State$LinkClicked = function (a) {
	return {$: 39, a: a};
};
var $author$project$State$UrlChanged = function (a) {
	return {$: 40, a: a};
};
var $elm$core$Basics$EQ = 1;
var $elm$core$Basics$GT = 2;
var $elm$core$Basics$LT = 0;
var $elm$core$List$cons = _List_cons;
var $elm$core$Dict$foldr = F3(
	function (func, acc, t) {
		foldr:
		while (true) {
			if (t.$ === -2) {
				return acc;
			} else {
				var key = t.b;
				var value = t.c;
				var left = t.d;
				var right = t.e;
				var $temp$func = func,
					$temp$acc = A3(
					func,
					key,
					value,
					A3($elm$core$Dict$foldr, func, acc, right)),
					$temp$t = left;
				func = $temp$func;
				acc = $temp$acc;
				t = $temp$t;
				continue foldr;
			}
		}
	});
var $elm$core$Dict$toList = function (dict) {
	return A3(
		$elm$core$Dict$foldr,
		F3(
			function (key, value, list) {
				return A2(
					$elm$core$List$cons,
					_Utils_Tuple2(key, value),
					list);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Dict$keys = function (dict) {
	return A3(
		$elm$core$Dict$foldr,
		F3(
			function (key, value, keyList) {
				return A2($elm$core$List$cons, key, keyList);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Set$toList = function (_v0) {
	var dict = _v0;
	return $elm$core$Dict$keys(dict);
};
var $elm$core$Elm$JsArray$foldr = _JsArray_foldr;
var $elm$core$Array$foldr = F3(
	function (func, baseCase, _v0) {
		var tree = _v0.c;
		var tail = _v0.d;
		var helper = F2(
			function (node, acc) {
				if (!node.$) {
					var subTree = node.a;
					return A3($elm$core$Elm$JsArray$foldr, helper, acc, subTree);
				} else {
					var values = node.a;
					return A3($elm$core$Elm$JsArray$foldr, func, acc, values);
				}
			});
		return A3(
			$elm$core$Elm$JsArray$foldr,
			helper,
			A3($elm$core$Elm$JsArray$foldr, func, baseCase, tail),
			tree);
	});
var $elm$core$Array$toList = function (array) {
	return A3($elm$core$Array$foldr, $elm$core$List$cons, _List_Nil, array);
};
var $elm$core$Result$Err = function (a) {
	return {$: 1, a: a};
};
var $elm$json$Json$Decode$Failure = F2(
	function (a, b) {
		return {$: 3, a: a, b: b};
	});
var $elm$json$Json$Decode$Field = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$json$Json$Decode$Index = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $elm$core$Result$Ok = function (a) {
	return {$: 0, a: a};
};
var $elm$json$Json$Decode$OneOf = function (a) {
	return {$: 2, a: a};
};
var $elm$core$Basics$False = 1;
var $elm$core$Basics$add = _Basics_add;
var $elm$core$Maybe$Just = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Maybe$Nothing = {$: 1};
var $elm$core$String$all = _String_all;
var $elm$core$Basics$and = _Basics_and;
var $elm$core$Basics$append = _Utils_append;
var $elm$json$Json$Encode$encode = _Json_encode;
var $elm$core$String$fromInt = _String_fromNumber;
var $elm$core$String$join = F2(
	function (sep, chunks) {
		return A2(
			_String_join,
			sep,
			_List_toArray(chunks));
	});
var $elm$core$String$split = F2(
	function (sep, string) {
		return _List_fromArray(
			A2(_String_split, sep, string));
	});
var $elm$json$Json$Decode$indent = function (str) {
	return A2(
		$elm$core$String$join,
		'\n    ',
		A2($elm$core$String$split, '\n', str));
};
var $elm$core$List$foldl = F3(
	function (func, acc, list) {
		foldl:
		while (true) {
			if (!list.b) {
				return acc;
			} else {
				var x = list.a;
				var xs = list.b;
				var $temp$func = func,
					$temp$acc = A2(func, x, acc),
					$temp$list = xs;
				func = $temp$func;
				acc = $temp$acc;
				list = $temp$list;
				continue foldl;
			}
		}
	});
var $elm$core$List$length = function (xs) {
	return A3(
		$elm$core$List$foldl,
		F2(
			function (_v0, i) {
				return i + 1;
			}),
		0,
		xs);
};
var $elm$core$List$map2 = _List_map2;
var $elm$core$Basics$le = _Utils_le;
var $elm$core$Basics$sub = _Basics_sub;
var $elm$core$List$rangeHelp = F3(
	function (lo, hi, list) {
		rangeHelp:
		while (true) {
			if (_Utils_cmp(lo, hi) < 1) {
				var $temp$lo = lo,
					$temp$hi = hi - 1,
					$temp$list = A2($elm$core$List$cons, hi, list);
				lo = $temp$lo;
				hi = $temp$hi;
				list = $temp$list;
				continue rangeHelp;
			} else {
				return list;
			}
		}
	});
var $elm$core$List$range = F2(
	function (lo, hi) {
		return A3($elm$core$List$rangeHelp, lo, hi, _List_Nil);
	});
var $elm$core$List$indexedMap = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$map2,
			f,
			A2(
				$elm$core$List$range,
				0,
				$elm$core$List$length(xs) - 1),
			xs);
	});
var $elm$core$Char$toCode = _Char_toCode;
var $elm$core$Char$isLower = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (97 <= code) && (code <= 122);
};
var $elm$core$Char$isUpper = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 90) && (65 <= code);
};
var $elm$core$Basics$or = _Basics_or;
var $elm$core$Char$isAlpha = function (_char) {
	return $elm$core$Char$isLower(_char) || $elm$core$Char$isUpper(_char);
};
var $elm$core$Char$isDigit = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 57) && (48 <= code);
};
var $elm$core$Char$isAlphaNum = function (_char) {
	return $elm$core$Char$isLower(_char) || ($elm$core$Char$isUpper(_char) || $elm$core$Char$isDigit(_char));
};
var $elm$core$List$reverse = function (list) {
	return A3($elm$core$List$foldl, $elm$core$List$cons, _List_Nil, list);
};
var $elm$core$String$uncons = _String_uncons;
var $elm$json$Json$Decode$errorOneOf = F2(
	function (i, error) {
		return '\n\n(' + ($elm$core$String$fromInt(i + 1) + (') ' + $elm$json$Json$Decode$indent(
			$elm$json$Json$Decode$errorToString(error))));
	});
var $elm$json$Json$Decode$errorToString = function (error) {
	return A2($elm$json$Json$Decode$errorToStringHelp, error, _List_Nil);
};
var $elm$json$Json$Decode$errorToStringHelp = F2(
	function (error, context) {
		errorToStringHelp:
		while (true) {
			switch (error.$) {
				case 0:
					var f = error.a;
					var err = error.b;
					var isSimple = function () {
						var _v1 = $elm$core$String$uncons(f);
						if (_v1.$ === 1) {
							return false;
						} else {
							var _v2 = _v1.a;
							var _char = _v2.a;
							var rest = _v2.b;
							return $elm$core$Char$isAlpha(_char) && A2($elm$core$String$all, $elm$core$Char$isAlphaNum, rest);
						}
					}();
					var fieldName = isSimple ? ('.' + f) : ('[\'' + (f + '\']'));
					var $temp$error = err,
						$temp$context = A2($elm$core$List$cons, fieldName, context);
					error = $temp$error;
					context = $temp$context;
					continue errorToStringHelp;
				case 1:
					var i = error.a;
					var err = error.b;
					var indexName = '[' + ($elm$core$String$fromInt(i) + ']');
					var $temp$error = err,
						$temp$context = A2($elm$core$List$cons, indexName, context);
					error = $temp$error;
					context = $temp$context;
					continue errorToStringHelp;
				case 2:
					var errors = error.a;
					if (!errors.b) {
						return 'Ran into a Json.Decode.oneOf with no possibilities' + function () {
							if (!context.b) {
								return '!';
							} else {
								return ' at json' + A2(
									$elm$core$String$join,
									'',
									$elm$core$List$reverse(context));
							}
						}();
					} else {
						if (!errors.b.b) {
							var err = errors.a;
							var $temp$error = err,
								$temp$context = context;
							error = $temp$error;
							context = $temp$context;
							continue errorToStringHelp;
						} else {
							var starter = function () {
								if (!context.b) {
									return 'Json.Decode.oneOf';
								} else {
									return 'The Json.Decode.oneOf at json' + A2(
										$elm$core$String$join,
										'',
										$elm$core$List$reverse(context));
								}
							}();
							var introduction = starter + (' failed in the following ' + ($elm$core$String$fromInt(
								$elm$core$List$length(errors)) + ' ways:'));
							return A2(
								$elm$core$String$join,
								'\n\n',
								A2(
									$elm$core$List$cons,
									introduction,
									A2($elm$core$List$indexedMap, $elm$json$Json$Decode$errorOneOf, errors)));
						}
					}
				default:
					var msg = error.a;
					var json = error.b;
					var introduction = function () {
						if (!context.b) {
							return 'Problem with the given value:\n\n';
						} else {
							return 'Problem with the value at json' + (A2(
								$elm$core$String$join,
								'',
								$elm$core$List$reverse(context)) + ':\n\n    ');
						}
					}();
					return introduction + ($elm$json$Json$Decode$indent(
						A2($elm$json$Json$Encode$encode, 4, json)) + ('\n\n' + msg));
			}
		}
	});
var $elm$core$Array$branchFactor = 32;
var $elm$core$Array$Array_elm_builtin = F4(
	function (a, b, c, d) {
		return {$: 0, a: a, b: b, c: c, d: d};
	});
var $elm$core$Elm$JsArray$empty = _JsArray_empty;
var $elm$core$Basics$ceiling = _Basics_ceiling;
var $elm$core$Basics$fdiv = _Basics_fdiv;
var $elm$core$Basics$logBase = F2(
	function (base, number) {
		return _Basics_log(number) / _Basics_log(base);
	});
var $elm$core$Basics$toFloat = _Basics_toFloat;
var $elm$core$Array$shiftStep = $elm$core$Basics$ceiling(
	A2($elm$core$Basics$logBase, 2, $elm$core$Array$branchFactor));
var $elm$core$Array$empty = A4($elm$core$Array$Array_elm_builtin, 0, $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, $elm$core$Elm$JsArray$empty);
var $elm$core$Elm$JsArray$initialize = _JsArray_initialize;
var $elm$core$Array$Leaf = function (a) {
	return {$: 1, a: a};
};
var $elm$core$Basics$apL = F2(
	function (f, x) {
		return f(x);
	});
var $elm$core$Basics$apR = F2(
	function (x, f) {
		return f(x);
	});
var $elm$core$Basics$eq = _Utils_equal;
var $elm$core$Basics$floor = _Basics_floor;
var $elm$core$Elm$JsArray$length = _JsArray_length;
var $elm$core$Basics$gt = _Utils_gt;
var $elm$core$Basics$max = F2(
	function (x, y) {
		return (_Utils_cmp(x, y) > 0) ? x : y;
	});
var $elm$core$Basics$mul = _Basics_mul;
var $elm$core$Array$SubTree = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Elm$JsArray$initializeFromList = _JsArray_initializeFromList;
var $elm$core$Array$compressNodes = F2(
	function (nodes, acc) {
		compressNodes:
		while (true) {
			var _v0 = A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodes);
			var node = _v0.a;
			var remainingNodes = _v0.b;
			var newAcc = A2(
				$elm$core$List$cons,
				$elm$core$Array$SubTree(node),
				acc);
			if (!remainingNodes.b) {
				return $elm$core$List$reverse(newAcc);
			} else {
				var $temp$nodes = remainingNodes,
					$temp$acc = newAcc;
				nodes = $temp$nodes;
				acc = $temp$acc;
				continue compressNodes;
			}
		}
	});
var $elm$core$Tuple$first = function (_v0) {
	var x = _v0.a;
	return x;
};
var $elm$core$Array$treeFromBuilder = F2(
	function (nodeList, nodeListSize) {
		treeFromBuilder:
		while (true) {
			var newNodeSize = $elm$core$Basics$ceiling(nodeListSize / $elm$core$Array$branchFactor);
			if (newNodeSize === 1) {
				return A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodeList).a;
			} else {
				var $temp$nodeList = A2($elm$core$Array$compressNodes, nodeList, _List_Nil),
					$temp$nodeListSize = newNodeSize;
				nodeList = $temp$nodeList;
				nodeListSize = $temp$nodeListSize;
				continue treeFromBuilder;
			}
		}
	});
var $elm$core$Array$builderToArray = F2(
	function (reverseNodeList, builder) {
		if (!builder.e) {
			return A4(
				$elm$core$Array$Array_elm_builtin,
				$elm$core$Elm$JsArray$length(builder.g),
				$elm$core$Array$shiftStep,
				$elm$core$Elm$JsArray$empty,
				builder.g);
		} else {
			var treeLen = builder.e * $elm$core$Array$branchFactor;
			var depth = $elm$core$Basics$floor(
				A2($elm$core$Basics$logBase, $elm$core$Array$branchFactor, treeLen - 1));
			var correctNodeList = reverseNodeList ? $elm$core$List$reverse(builder.h) : builder.h;
			var tree = A2($elm$core$Array$treeFromBuilder, correctNodeList, builder.e);
			return A4(
				$elm$core$Array$Array_elm_builtin,
				$elm$core$Elm$JsArray$length(builder.g) + treeLen,
				A2($elm$core$Basics$max, 5, depth * $elm$core$Array$shiftStep),
				tree,
				builder.g);
		}
	});
var $elm$core$Basics$idiv = _Basics_idiv;
var $elm$core$Basics$lt = _Utils_lt;
var $elm$core$Array$initializeHelp = F5(
	function (fn, fromIndex, len, nodeList, tail) {
		initializeHelp:
		while (true) {
			if (fromIndex < 0) {
				return A2(
					$elm$core$Array$builderToArray,
					false,
					{h: nodeList, e: (len / $elm$core$Array$branchFactor) | 0, g: tail});
			} else {
				var leaf = $elm$core$Array$Leaf(
					A3($elm$core$Elm$JsArray$initialize, $elm$core$Array$branchFactor, fromIndex, fn));
				var $temp$fn = fn,
					$temp$fromIndex = fromIndex - $elm$core$Array$branchFactor,
					$temp$len = len,
					$temp$nodeList = A2($elm$core$List$cons, leaf, nodeList),
					$temp$tail = tail;
				fn = $temp$fn;
				fromIndex = $temp$fromIndex;
				len = $temp$len;
				nodeList = $temp$nodeList;
				tail = $temp$tail;
				continue initializeHelp;
			}
		}
	});
var $elm$core$Basics$remainderBy = _Basics_remainderBy;
var $elm$core$Array$initialize = F2(
	function (len, fn) {
		if (len <= 0) {
			return $elm$core$Array$empty;
		} else {
			var tailLen = len % $elm$core$Array$branchFactor;
			var tail = A3($elm$core$Elm$JsArray$initialize, tailLen, len - tailLen, fn);
			var initialFromIndex = (len - tailLen) - $elm$core$Array$branchFactor;
			return A5($elm$core$Array$initializeHelp, fn, initialFromIndex, len, _List_Nil, tail);
		}
	});
var $elm$core$Basics$True = 0;
var $elm$core$Result$isOk = function (result) {
	if (!result.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$json$Json$Decode$map = _Json_map1;
var $elm$json$Json$Decode$map2 = _Json_map2;
var $elm$json$Json$Decode$succeed = _Json_succeed;
var $elm$virtual_dom$VirtualDom$toHandlerInt = function (handler) {
	switch (handler.$) {
		case 0:
			return 0;
		case 1:
			return 1;
		case 2:
			return 2;
		default:
			return 3;
	}
};
var $elm$browser$Browser$External = function (a) {
	return {$: 1, a: a};
};
var $elm$browser$Browser$Internal = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Basics$identity = function (x) {
	return x;
};
var $elm$browser$Browser$Dom$NotFound = $elm$core$Basics$identity;
var $elm$url$Url$Http = 0;
var $elm$url$Url$Https = 1;
var $elm$url$Url$Url = F6(
	function (protocol, host, port_, path, query, fragment) {
		return {bJ: fragment, bN: host, A: path, b$: port_, b3: protocol, dd: query};
	});
var $elm$core$String$contains = _String_contains;
var $elm$core$String$length = _String_length;
var $elm$core$String$slice = _String_slice;
var $elm$core$String$dropLeft = F2(
	function (n, string) {
		return (n < 1) ? string : A3(
			$elm$core$String$slice,
			n,
			$elm$core$String$length(string),
			string);
	});
var $elm$core$String$indexes = _String_indexes;
var $elm$core$String$isEmpty = function (string) {
	return string === '';
};
var $elm$core$String$left = F2(
	function (n, string) {
		return (n < 1) ? '' : A3($elm$core$String$slice, 0, n, string);
	});
var $elm$core$String$toInt = _String_toInt;
var $elm$url$Url$chompBeforePath = F5(
	function (protocol, path, params, frag, str) {
		if ($elm$core$String$isEmpty(str) || A2($elm$core$String$contains, '@', str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, ':', str);
			if (!_v0.b) {
				return $elm$core$Maybe$Just(
					A6($elm$url$Url$Url, protocol, str, $elm$core$Maybe$Nothing, path, params, frag));
			} else {
				if (!_v0.b.b) {
					var i = _v0.a;
					var _v1 = $elm$core$String$toInt(
						A2($elm$core$String$dropLeft, i + 1, str));
					if (_v1.$ === 1) {
						return $elm$core$Maybe$Nothing;
					} else {
						var port_ = _v1;
						return $elm$core$Maybe$Just(
							A6(
								$elm$url$Url$Url,
								protocol,
								A2($elm$core$String$left, i, str),
								port_,
								path,
								params,
								frag));
					}
				} else {
					return $elm$core$Maybe$Nothing;
				}
			}
		}
	});
var $elm$url$Url$chompBeforeQuery = F4(
	function (protocol, params, frag, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '/', str);
			if (!_v0.b) {
				return A5($elm$url$Url$chompBeforePath, protocol, '/', params, frag, str);
			} else {
				var i = _v0.a;
				return A5(
					$elm$url$Url$chompBeforePath,
					protocol,
					A2($elm$core$String$dropLeft, i, str),
					params,
					frag,
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$url$Url$chompBeforeFragment = F3(
	function (protocol, frag, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '?', str);
			if (!_v0.b) {
				return A4($elm$url$Url$chompBeforeQuery, protocol, $elm$core$Maybe$Nothing, frag, str);
			} else {
				var i = _v0.a;
				return A4(
					$elm$url$Url$chompBeforeQuery,
					protocol,
					$elm$core$Maybe$Just(
						A2($elm$core$String$dropLeft, i + 1, str)),
					frag,
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$url$Url$chompAfterProtocol = F2(
	function (protocol, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '#', str);
			if (!_v0.b) {
				return A3($elm$url$Url$chompBeforeFragment, protocol, $elm$core$Maybe$Nothing, str);
			} else {
				var i = _v0.a;
				return A3(
					$elm$url$Url$chompBeforeFragment,
					protocol,
					$elm$core$Maybe$Just(
						A2($elm$core$String$dropLeft, i + 1, str)),
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$core$String$startsWith = _String_startsWith;
var $elm$url$Url$fromString = function (str) {
	return A2($elm$core$String$startsWith, 'http://', str) ? A2(
		$elm$url$Url$chompAfterProtocol,
		0,
		A2($elm$core$String$dropLeft, 7, str)) : (A2($elm$core$String$startsWith, 'https://', str) ? A2(
		$elm$url$Url$chompAfterProtocol,
		1,
		A2($elm$core$String$dropLeft, 8, str)) : $elm$core$Maybe$Nothing);
};
var $elm$core$Basics$never = function (_v0) {
	never:
	while (true) {
		var nvr = _v0;
		var $temp$_v0 = nvr;
		_v0 = $temp$_v0;
		continue never;
	}
};
var $elm$core$Task$Perform = $elm$core$Basics$identity;
var $elm$core$Task$succeed = _Scheduler_succeed;
var $elm$core$Task$init = $elm$core$Task$succeed(0);
var $elm$core$List$foldrHelper = F4(
	function (fn, acc, ctr, ls) {
		if (!ls.b) {
			return acc;
		} else {
			var a = ls.a;
			var r1 = ls.b;
			if (!r1.b) {
				return A2(fn, a, acc);
			} else {
				var b = r1.a;
				var r2 = r1.b;
				if (!r2.b) {
					return A2(
						fn,
						a,
						A2(fn, b, acc));
				} else {
					var c = r2.a;
					var r3 = r2.b;
					if (!r3.b) {
						return A2(
							fn,
							a,
							A2(
								fn,
								b,
								A2(fn, c, acc)));
					} else {
						var d = r3.a;
						var r4 = r3.b;
						var res = (ctr > 500) ? A3(
							$elm$core$List$foldl,
							fn,
							acc,
							$elm$core$List$reverse(r4)) : A4($elm$core$List$foldrHelper, fn, acc, ctr + 1, r4);
						return A2(
							fn,
							a,
							A2(
								fn,
								b,
								A2(
									fn,
									c,
									A2(fn, d, res))));
					}
				}
			}
		}
	});
var $elm$core$List$foldr = F3(
	function (fn, acc, ls) {
		return A4($elm$core$List$foldrHelper, fn, acc, 0, ls);
	});
var $elm$core$List$map = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$foldr,
			F2(
				function (x, acc) {
					return A2(
						$elm$core$List$cons,
						f(x),
						acc);
				}),
			_List_Nil,
			xs);
	});
var $elm$core$Task$andThen = _Scheduler_andThen;
var $elm$core$Task$map = F2(
	function (func, taskA) {
		return A2(
			$elm$core$Task$andThen,
			function (a) {
				return $elm$core$Task$succeed(
					func(a));
			},
			taskA);
	});
var $elm$core$Task$map2 = F3(
	function (func, taskA, taskB) {
		return A2(
			$elm$core$Task$andThen,
			function (a) {
				return A2(
					$elm$core$Task$andThen,
					function (b) {
						return $elm$core$Task$succeed(
							A2(func, a, b));
					},
					taskB);
			},
			taskA);
	});
var $elm$core$Task$sequence = function (tasks) {
	return A3(
		$elm$core$List$foldr,
		$elm$core$Task$map2($elm$core$List$cons),
		$elm$core$Task$succeed(_List_Nil),
		tasks);
};
var $elm$core$Platform$sendToApp = _Platform_sendToApp;
var $elm$core$Task$spawnCmd = F2(
	function (router, _v0) {
		var task = _v0;
		return _Scheduler_spawn(
			A2(
				$elm$core$Task$andThen,
				$elm$core$Platform$sendToApp(router),
				task));
	});
var $elm$core$Task$onEffects = F3(
	function (router, commands, state) {
		return A2(
			$elm$core$Task$map,
			function (_v0) {
				return 0;
			},
			$elm$core$Task$sequence(
				A2(
					$elm$core$List$map,
					$elm$core$Task$spawnCmd(router),
					commands)));
	});
var $elm$core$Task$onSelfMsg = F3(
	function (_v0, _v1, _v2) {
		return $elm$core$Task$succeed(0);
	});
var $elm$core$Task$cmdMap = F2(
	function (tagger, _v0) {
		var task = _v0;
		return A2($elm$core$Task$map, tagger, task);
	});
_Platform_effectManagers['Task'] = _Platform_createManager($elm$core$Task$init, $elm$core$Task$onEffects, $elm$core$Task$onSelfMsg, $elm$core$Task$cmdMap);
var $elm$core$Task$command = _Platform_leaf('Task');
var $elm$core$Task$perform = F2(
	function (toMessage, task) {
		return $elm$core$Task$command(
			A2($elm$core$Task$map, toMessage, task));
	});
var $elm$browser$Browser$application = _Browser_application;
var $author$project$State$PortalExchange = function (a) {
	return {$: 31, a: a};
};
var $author$project$State$PortalLoaded = function (a) {
	return {$: 33, a: a};
};
var $author$project$State$TodayChanged = function (a) {
	return {$: 143, a: a};
};
var $author$project$State$AcceptLoad = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$json$Json$Encode$list = F2(
	function (func, entries) {
		return _Json_wrap(
			A3(
				$elm$core$List$foldl,
				_Json_addEntry(func),
				_Json_emptyArray(0),
				entries));
	});
var $elm$json$Json$Encode$string = _Json_wrap;
var $elm$core$Maybe$withDefault = F2(
	function (_default, maybe) {
		if (!maybe.$) {
			var value = maybe.a;
			return value;
		} else {
			return _default;
		}
	});
var $author$project$Main$loadKey = function (model) {
	return A2(
		$elm$json$Json$Encode$encode,
		0,
		A2(
			$elm$json$Json$Encode$list,
			$elm$json$Json$Encode$string,
			_List_fromArray(
				[
					model.a_.A,
					A2($elm$core$Maybe$withDefault, '', model.du),
					$elm$core$String$fromInt(model.as),
					$elm$core$String$fromInt(model.c8),
					model.dc,
					model.aG,
					model.cS,
					model.cQ,
					model.cR,
					model.dm,
					model.bb,
					model.Z,
					model.a7,
					model.dl ? 'asc' : 'desc'
				])));
};
var $author$project$Main$loadKeyFor = F2(
	function (msg, model) {
		if (msg.$ === 51) {
			return A2(
				$elm$json$Json$Encode$encode,
				0,
				A2(
					$elm$json$Json$Encode$list,
					$elm$json$Json$Encode$string,
					_List_fromArray(
						[
							A2($elm$core$Maybe$withDefault, '', model.du),
							$elm$core$String$fromInt(model.aB)
						])));
		} else {
			return $author$project$Main$loadKey(model);
		}
	});
var $author$project$Main$acceptLoad = F3(
	function (model, constructor, result) {
		var loaded = constructor(result);
		return A2(
			$author$project$State$AcceptLoad,
			A2($author$project$Main$loadKeyFor, loaded, model),
			loaded);
	});
var $elm$core$Basics$always = F2(
	function (a, _v0) {
		return a;
	});
var $elm$core$Platform$Cmd$batch = _Platform_batch;
var $elm$core$Basics$composeL = F3(
	function (g, f, x) {
		return g(
			f(x));
	});
var $author$project$Api$computeBase = function (_v0) {
	return '';
};
var $elm$core$Dict$RBEmpty_elm_builtin = {$: -2};
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $elm$core$Dict$Black = 1;
var $elm$core$Dict$RBNode_elm_builtin = F5(
	function (a, b, c, d, e) {
		return {$: -1, a: a, b: b, c: c, d: d, e: e};
	});
var $elm$core$Dict$Red = 0;
var $elm$core$Dict$balance = F5(
	function (color, key, value, left, right) {
		if ((right.$ === -1) && (!right.a)) {
			var _v1 = right.a;
			var rK = right.b;
			var rV = right.c;
			var rLeft = right.d;
			var rRight = right.e;
			if ((left.$ === -1) && (!left.a)) {
				var _v3 = left.a;
				var lK = left.b;
				var lV = left.c;
				var lLeft = left.d;
				var lRight = left.e;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					0,
					key,
					value,
					A5($elm$core$Dict$RBNode_elm_builtin, 1, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					color,
					rK,
					rV,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, left, rLeft),
					rRight);
			}
		} else {
			if ((((left.$ === -1) && (!left.a)) && (left.d.$ === -1)) && (!left.d.a)) {
				var _v5 = left.a;
				var lK = left.b;
				var lV = left.c;
				var _v6 = left.d;
				var _v7 = _v6.a;
				var llK = _v6.b;
				var llV = _v6.c;
				var llLeft = _v6.d;
				var llRight = _v6.e;
				var lRight = left.e;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					0,
					lK,
					lV,
					A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 1, key, value, lRight, right));
			} else {
				return A5($elm$core$Dict$RBNode_elm_builtin, color, key, value, left, right);
			}
		}
	});
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$insertHelp = F3(
	function (key, value, dict) {
		if (dict.$ === -2) {
			return A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin);
		} else {
			var nColor = dict.a;
			var nKey = dict.b;
			var nValue = dict.c;
			var nLeft = dict.d;
			var nRight = dict.e;
			var _v1 = A2($elm$core$Basics$compare, key, nKey);
			switch (_v1) {
				case 0:
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						A3($elm$core$Dict$insertHelp, key, value, nLeft),
						nRight);
				case 1:
					return A5($elm$core$Dict$RBNode_elm_builtin, nColor, nKey, value, nLeft, nRight);
				default:
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						nLeft,
						A3($elm$core$Dict$insertHelp, key, value, nRight));
			}
		}
	});
var $elm$core$Dict$insert = F3(
	function (key, value, dict) {
		var _v0 = A3($elm$core$Dict$insertHelp, key, value, dict);
		if ((_v0.$ === -1) && (!_v0.a)) {
			var _v1 = _v0.a;
			var k = _v0.b;
			var v = _v0.c;
			var l = _v0.d;
			var r = _v0.e;
			return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
		} else {
			var x = _v0;
			return x;
		}
	});
var $elm$core$Dict$fromList = function (assocs) {
	return A3(
		$elm$core$List$foldl,
		F2(
			function (_v0, dict) {
				var key = _v0.a;
				var value = _v0.b;
				return A3($elm$core$Dict$insert, key, value, dict);
			}),
		$elm$core$Dict$empty,
		assocs);
};
var $author$project$Features$defaults = function (section) {
	return $elm$core$Dict$fromList(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'status',
				function () {
					switch (section) {
						case 'documents':
							return 'Missing';
						case 'appointments':
							return 'Scheduled';
						case 'invoices':
							return 'Draft';
						default:
							return 'Pending';
					}
				}()),
				_Utils_Tuple2('required', 'true'),
				_Utils_Tuple2('enabled', 'true'),
				_Utils_Tuple2('priority', 'Medium'),
				_Utils_Tuple2(
				'entity',
				(section === 'merge') ? 'leads' : 'tasks'),
				_Utils_Tuple2('currency', 'PHP'),
				_Utils_Tuple2('daysBefore', '1'),
				_Utils_Tuple2('escalateAfter', '2'),
				_Utils_Tuple2('days', '7'),
				_Utils_Tuple2('mine', 'true'),
				_Utils_Tuple2('overdue', 'false'),
				_Utils_Tuple2('assignments', 'true'),
				_Utils_Tuple2('deadlines', 'true'),
				_Utils_Tuple2('documents', 'true'),
				_Utils_Tuple2('escalations', 'true'),
				_Utils_Tuple2('emailEnabled', 'true')
			]));
};
var $elm$core$Set$Set_elm_builtin = $elm$core$Basics$identity;
var $elm$core$Set$empty = $elm$core$Dict$empty;
var $author$project$State$emptyAddLead = {aJ: 'Canada', ap: '', bK: '', _: '', aa: '', bZ: '', ad: 'Warm', ae: 'Student Visa', ah: 'Website', $7: 'New Lead'};
var $author$project$State$emptyAddTask = {a4: '', aK: '', aP: '', bl: 'Medium', ay: ''};
var $author$project$State$emptyClientForm = {ap: '', bK: '', bX: '', bZ: '', m: 1};
var $author$project$State$emptyEditLeadFrom = {a2: $elm$core$Maybe$Nothing, aJ: 'Canada', ap: '', bK: '', aN: '', _: '', aa: '', bZ: '', ad: 'Warm', m: 1, ae: 'Student Visa', ah: 'Website', $7: 'New Lead'};
var $author$project$State$emptyUserForm = {ap: '', t: '', ab: '', m: 1, aX: 'consultant', ch: $elm$core$Maybe$Nothing};
var $elm$json$Json$Encode$null = _Json_encodeNull;
var $author$project$State$Dashboard = {$: 0};
var $elm$url$Url$Parser$State = F5(
	function (visited, unvisited, params, frag, value) {
		return {O: frag, Q: params, K: unvisited, E: value, U: visited};
	});
var $elm$url$Url$Parser$getFirstMatch = function (states) {
	getFirstMatch:
	while (true) {
		if (!states.b) {
			return $elm$core$Maybe$Nothing;
		} else {
			var state = states.a;
			var rest = states.b;
			var _v1 = state.K;
			if (!_v1.b) {
				return $elm$core$Maybe$Just(state.E);
			} else {
				if ((_v1.a === '') && (!_v1.b.b)) {
					return $elm$core$Maybe$Just(state.E);
				} else {
					var $temp$states = rest;
					states = $temp$states;
					continue getFirstMatch;
				}
			}
		}
	}
};
var $elm$url$Url$Parser$removeFinalEmpty = function (segments) {
	if (!segments.b) {
		return _List_Nil;
	} else {
		if ((segments.a === '') && (!segments.b.b)) {
			return _List_Nil;
		} else {
			var segment = segments.a;
			var rest = segments.b;
			return A2(
				$elm$core$List$cons,
				segment,
				$elm$url$Url$Parser$removeFinalEmpty(rest));
		}
	}
};
var $elm$url$Url$Parser$preparePath = function (path) {
	var _v0 = A2($elm$core$String$split, '/', path);
	if (_v0.b && (_v0.a === '')) {
		var segments = _v0.b;
		return $elm$url$Url$Parser$removeFinalEmpty(segments);
	} else {
		var segments = _v0;
		return $elm$url$Url$Parser$removeFinalEmpty(segments);
	}
};
var $elm$url$Url$Parser$addToParametersHelp = F2(
	function (value, maybeList) {
		if (maybeList.$ === 1) {
			return $elm$core$Maybe$Just(
				_List_fromArray(
					[value]));
		} else {
			var list = maybeList.a;
			return $elm$core$Maybe$Just(
				A2($elm$core$List$cons, value, list));
		}
	});
var $elm$url$Url$percentDecode = _Url_percentDecode;
var $elm$core$Dict$get = F2(
	function (targetKey, dict) {
		get:
		while (true) {
			if (dict.$ === -2) {
				return $elm$core$Maybe$Nothing;
			} else {
				var key = dict.b;
				var value = dict.c;
				var left = dict.d;
				var right = dict.e;
				var _v1 = A2($elm$core$Basics$compare, targetKey, key);
				switch (_v1) {
					case 0:
						var $temp$targetKey = targetKey,
							$temp$dict = left;
						targetKey = $temp$targetKey;
						dict = $temp$dict;
						continue get;
					case 1:
						return $elm$core$Maybe$Just(value);
					default:
						var $temp$targetKey = targetKey,
							$temp$dict = right;
						targetKey = $temp$targetKey;
						dict = $temp$dict;
						continue get;
				}
			}
		}
	});
var $elm$core$Dict$getMin = function (dict) {
	getMin:
	while (true) {
		if ((dict.$ === -1) && (dict.d.$ === -1)) {
			var left = dict.d;
			var $temp$dict = left;
			dict = $temp$dict;
			continue getMin;
		} else {
			return dict;
		}
	}
};
var $elm$core$Dict$moveRedLeft = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.e.d.$ === -1) && (!dict.e.d.a)) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var lLeft = _v1.d;
			var lRight = _v1.e;
			var _v2 = dict.e;
			var rClr = _v2.a;
			var rK = _v2.b;
			var rV = _v2.c;
			var rLeft = _v2.d;
			var _v3 = rLeft.a;
			var rlK = rLeft.b;
			var rlV = rLeft.c;
			var rlL = rLeft.d;
			var rlR = rLeft.e;
			var rRight = _v2.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				0,
				rlK,
				rlV,
				A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					rlL),
				A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rlR, rRight));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v4 = dict.d;
			var lClr = _v4.a;
			var lK = _v4.b;
			var lV = _v4.c;
			var lLeft = _v4.d;
			var lRight = _v4.e;
			var _v5 = dict.e;
			var rClr = _v5.a;
			var rK = _v5.b;
			var rV = _v5.c;
			var rLeft = _v5.d;
			var rRight = _v5.e;
			if (clr === 1) {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$moveRedRight = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.d.d.$ === -1) && (!dict.d.d.a)) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var _v2 = _v1.d;
			var _v3 = _v2.a;
			var llK = _v2.b;
			var llV = _v2.c;
			var llLeft = _v2.d;
			var llRight = _v2.e;
			var lRight = _v1.e;
			var _v4 = dict.e;
			var rClr = _v4.a;
			var rK = _v4.b;
			var rV = _v4.c;
			var rLeft = _v4.d;
			var rRight = _v4.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				0,
				lK,
				lV,
				A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
				A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					lRight,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight)));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v5 = dict.d;
			var lClr = _v5.a;
			var lK = _v5.b;
			var lV = _v5.c;
			var lLeft = _v5.d;
			var lRight = _v5.e;
			var _v6 = dict.e;
			var rClr = _v6.a;
			var rK = _v6.b;
			var rV = _v6.c;
			var rLeft = _v6.d;
			var rRight = _v6.e;
			if (clr === 1) {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$removeHelpPrepEQGT = F7(
	function (targetKey, dict, color, key, value, left, right) {
		if ((left.$ === -1) && (!left.a)) {
			var _v1 = left.a;
			var lK = left.b;
			var lV = left.c;
			var lLeft = left.d;
			var lRight = left.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				lK,
				lV,
				lLeft,
				A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, lRight, right));
		} else {
			_v2$2:
			while (true) {
				if ((right.$ === -1) && (right.a === 1)) {
					if (right.d.$ === -1) {
						if (right.d.a === 1) {
							var _v3 = right.a;
							var _v4 = right.d;
							var _v5 = _v4.a;
							return $elm$core$Dict$moveRedRight(dict);
						} else {
							break _v2$2;
						}
					} else {
						var _v6 = right.a;
						var _v7 = right.d;
						return $elm$core$Dict$moveRedRight(dict);
					}
				} else {
					break _v2$2;
				}
			}
			return dict;
		}
	});
var $elm$core$Dict$removeMin = function (dict) {
	if ((dict.$ === -1) && (dict.d.$ === -1)) {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var lColor = left.a;
		var lLeft = left.d;
		var right = dict.e;
		if (lColor === 1) {
			if ((lLeft.$ === -1) && (!lLeft.a)) {
				var _v3 = lLeft.a;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					color,
					key,
					value,
					$elm$core$Dict$removeMin(left),
					right);
			} else {
				var _v4 = $elm$core$Dict$moveRedLeft(dict);
				if (_v4.$ === -1) {
					var nColor = _v4.a;
					var nKey = _v4.b;
					var nValue = _v4.c;
					var nLeft = _v4.d;
					var nRight = _v4.e;
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						$elm$core$Dict$removeMin(nLeft),
						nRight);
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			}
		} else {
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				key,
				value,
				$elm$core$Dict$removeMin(left),
				right);
		}
	} else {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	}
};
var $elm$core$Dict$removeHelp = F2(
	function (targetKey, dict) {
		if (dict.$ === -2) {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		} else {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			if (_Utils_cmp(targetKey, key) < 0) {
				if ((left.$ === -1) && (left.a === 1)) {
					var _v4 = left.a;
					var lLeft = left.d;
					if ((lLeft.$ === -1) && (!lLeft.a)) {
						var _v6 = lLeft.a;
						return A5(
							$elm$core$Dict$RBNode_elm_builtin,
							color,
							key,
							value,
							A2($elm$core$Dict$removeHelp, targetKey, left),
							right);
					} else {
						var _v7 = $elm$core$Dict$moveRedLeft(dict);
						if (_v7.$ === -1) {
							var nColor = _v7.a;
							var nKey = _v7.b;
							var nValue = _v7.c;
							var nLeft = _v7.d;
							var nRight = _v7.e;
							return A5(
								$elm$core$Dict$balance,
								nColor,
								nKey,
								nValue,
								A2($elm$core$Dict$removeHelp, targetKey, nLeft),
								nRight);
						} else {
							return $elm$core$Dict$RBEmpty_elm_builtin;
						}
					}
				} else {
					return A5(
						$elm$core$Dict$RBNode_elm_builtin,
						color,
						key,
						value,
						A2($elm$core$Dict$removeHelp, targetKey, left),
						right);
				}
			} else {
				return A2(
					$elm$core$Dict$removeHelpEQGT,
					targetKey,
					A7($elm$core$Dict$removeHelpPrepEQGT, targetKey, dict, color, key, value, left, right));
			}
		}
	});
var $elm$core$Dict$removeHelpEQGT = F2(
	function (targetKey, dict) {
		if (dict.$ === -1) {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			if (_Utils_eq(targetKey, key)) {
				var _v1 = $elm$core$Dict$getMin(right);
				if (_v1.$ === -1) {
					var minKey = _v1.b;
					var minValue = _v1.c;
					return A5(
						$elm$core$Dict$balance,
						color,
						minKey,
						minValue,
						left,
						$elm$core$Dict$removeMin(right));
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			} else {
				return A5(
					$elm$core$Dict$balance,
					color,
					key,
					value,
					left,
					A2($elm$core$Dict$removeHelp, targetKey, right));
			}
		} else {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		}
	});
var $elm$core$Dict$remove = F2(
	function (key, dict) {
		var _v0 = A2($elm$core$Dict$removeHelp, key, dict);
		if ((_v0.$ === -1) && (!_v0.a)) {
			var _v1 = _v0.a;
			var k = _v0.b;
			var v = _v0.c;
			var l = _v0.d;
			var r = _v0.e;
			return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
		} else {
			var x = _v0;
			return x;
		}
	});
var $elm$core$Dict$update = F3(
	function (targetKey, alter, dictionary) {
		var _v0 = alter(
			A2($elm$core$Dict$get, targetKey, dictionary));
		if (!_v0.$) {
			var value = _v0.a;
			return A3($elm$core$Dict$insert, targetKey, value, dictionary);
		} else {
			return A2($elm$core$Dict$remove, targetKey, dictionary);
		}
	});
var $elm$url$Url$Parser$addParam = F2(
	function (segment, dict) {
		var _v0 = A2($elm$core$String$split, '=', segment);
		if ((_v0.b && _v0.b.b) && (!_v0.b.b.b)) {
			var rawKey = _v0.a;
			var _v1 = _v0.b;
			var rawValue = _v1.a;
			var _v2 = $elm$url$Url$percentDecode(rawKey);
			if (_v2.$ === 1) {
				return dict;
			} else {
				var key = _v2.a;
				var _v3 = $elm$url$Url$percentDecode(rawValue);
				if (_v3.$ === 1) {
					return dict;
				} else {
					var value = _v3.a;
					return A3(
						$elm$core$Dict$update,
						key,
						$elm$url$Url$Parser$addToParametersHelp(value),
						dict);
				}
			}
		} else {
			return dict;
		}
	});
var $elm$url$Url$Parser$prepareQuery = function (maybeQuery) {
	if (maybeQuery.$ === 1) {
		return $elm$core$Dict$empty;
	} else {
		var qry = maybeQuery.a;
		return A3(
			$elm$core$List$foldr,
			$elm$url$Url$Parser$addParam,
			$elm$core$Dict$empty,
			A2($elm$core$String$split, '&', qry));
	}
};
var $elm$url$Url$Parser$parse = F2(
	function (_v0, url) {
		var parser = _v0;
		return $elm$url$Url$Parser$getFirstMatch(
			parser(
				A5(
					$elm$url$Url$Parser$State,
					_List_Nil,
					$elm$url$Url$Parser$preparePath(url.A),
					$elm$url$Url$Parser$prepareQuery(url.dd),
					url.bJ,
					$elm$core$Basics$identity)));
	});
var $author$project$State$AuditPage = {$: 7};
var $author$project$State$ClientDetailPage = function (a) {
	return {$: 4, a: a};
};
var $author$project$State$ClientsPage = {$: 3};
var $author$project$State$LeadDetailPage = function (a) {
	return {$: 2, a: a};
};
var $author$project$State$LeadsPage = {$: 1};
var $author$project$State$TasksPage = {$: 5};
var $author$project$State$UsersPage = {$: 6};
var $author$project$State$WorkspacePage = function (a) {
	return {$: 8, a: a};
};
var $elm$url$Url$Parser$Parser = $elm$core$Basics$identity;
var $elm$url$Url$Parser$custom = F2(
	function (tipe, stringToSomething) {
		return function (_v0) {
			var visited = _v0.U;
			var unvisited = _v0.K;
			var params = _v0.Q;
			var frag = _v0.O;
			var value = _v0.E;
			if (!unvisited.b) {
				return _List_Nil;
			} else {
				var next = unvisited.a;
				var rest = unvisited.b;
				var _v2 = stringToSomething(next);
				if (!_v2.$) {
					var nextValue = _v2.a;
					return _List_fromArray(
						[
							A5(
							$elm$url$Url$Parser$State,
							A2($elm$core$List$cons, next, visited),
							rest,
							params,
							frag,
							value(nextValue))
						]);
				} else {
					return _List_Nil;
				}
			}
		};
	});
var $elm$url$Url$Parser$int = A2($elm$url$Url$Parser$custom, 'NUMBER', $elm$core$String$toInt);
var $elm$url$Url$Parser$mapState = F2(
	function (func, _v0) {
		var visited = _v0.U;
		var unvisited = _v0.K;
		var params = _v0.Q;
		var frag = _v0.O;
		var value = _v0.E;
		return A5(
			$elm$url$Url$Parser$State,
			visited,
			unvisited,
			params,
			frag,
			func(value));
	});
var $elm$url$Url$Parser$map = F2(
	function (subValue, _v0) {
		var parseArg = _v0;
		return function (_v1) {
			var visited = _v1.U;
			var unvisited = _v1.K;
			var params = _v1.Q;
			var frag = _v1.O;
			var value = _v1.E;
			return A2(
				$elm$core$List$map,
				$elm$url$Url$Parser$mapState(value),
				parseArg(
					A5($elm$url$Url$Parser$State, visited, unvisited, params, frag, subValue)));
		};
	});
var $elm$core$List$append = F2(
	function (xs, ys) {
		if (!ys.b) {
			return xs;
		} else {
			return A3($elm$core$List$foldr, $elm$core$List$cons, ys, xs);
		}
	});
var $elm$core$List$concat = function (lists) {
	return A3($elm$core$List$foldr, $elm$core$List$append, _List_Nil, lists);
};
var $elm$core$List$concatMap = F2(
	function (f, list) {
		return $elm$core$List$concat(
			A2($elm$core$List$map, f, list));
	});
var $elm$url$Url$Parser$oneOf = function (parsers) {
	return function (state) {
		return A2(
			$elm$core$List$concatMap,
			function (_v0) {
				var parser = _v0;
				return parser(state);
			},
			parsers);
	};
};
var $elm$url$Url$Parser$s = function (str) {
	return function (_v0) {
		var visited = _v0.U;
		var unvisited = _v0.K;
		var params = _v0.Q;
		var frag = _v0.O;
		var value = _v0.E;
		if (!unvisited.b) {
			return _List_Nil;
		} else {
			var next = unvisited.a;
			var rest = unvisited.b;
			return _Utils_eq(next, str) ? _List_fromArray(
				[
					A5(
					$elm$url$Url$Parser$State,
					A2($elm$core$List$cons, next, visited),
					rest,
					params,
					frag,
					value)
				]) : _List_Nil;
		}
	};
};
var $elm$url$Url$Parser$slash = F2(
	function (_v0, _v1) {
		var parseBefore = _v0;
		var parseAfter = _v1;
		return function (state) {
			return A2(
				$elm$core$List$concatMap,
				parseAfter,
				parseBefore(state));
		};
	});
var $elm$url$Url$Parser$string = A2($elm$url$Url$Parser$custom, 'STRING', $elm$core$Maybe$Just);
var $elm$url$Url$Parser$top = function (state) {
	return _List_fromArray(
		[state]);
};
var $author$project$State$routeParser = $elm$url$Url$Parser$oneOf(
	_List_fromArray(
		[
			A2(
			$elm$url$Url$Parser$map,
			function (section) {
				return $author$project$State$WorkspacePage('work/' + section);
			},
			A2(
				$elm$url$Url$Parser$slash,
				$elm$url$Url$Parser$s('work'),
				$elm$url$Url$Parser$string)),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$WorkspacePage('reminders'),
			$elm$url$Url$Parser$s('reminders')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$WorkspacePage('duplicates'),
			$elm$url$Url$Parser$s('duplicates')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$WorkspacePage('archive'),
			$elm$url$Url$Parser$s('archive')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$WorkspacePage('metrics'),
			$elm$url$Url$Parser$s('system')),
			A2($elm$url$Url$Parser$map, $author$project$State$Dashboard, $elm$url$Url$Parser$top),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$LeadsPage,
			$elm$url$Url$Parser$s('leads')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$LeadDetailPage,
			A2(
				$elm$url$Url$Parser$slash,
				$elm$url$Url$Parser$s('leads'),
				$elm$url$Url$Parser$int)),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$ClientsPage,
			$elm$url$Url$Parser$s('clients')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$ClientDetailPage,
			A2(
				$elm$url$Url$Parser$slash,
				$elm$url$Url$Parser$s('clients'),
				$elm$url$Url$Parser$int)),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$TasksPage,
			$elm$url$Url$Parser$s('tasks')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$UsersPage,
			$elm$url$Url$Parser$s('users')),
			A2(
			$elm$url$Url$Parser$map,
			$author$project$State$AuditPage,
			$elm$url$Url$Parser$s('audit'))
		]));
var $author$project$State$routeOf = function (url) {
	return A2(
		$elm$core$Maybe$withDefault,
		$author$project$State$Dashboard,
		A2($elm$url$Url$Parser$parse, $author$project$State$routeParser, url));
};
var $author$project$State$initialModel = F2(
	function (key, url) {
		return {
			aC: $author$project$State$emptyAddLead,
			k: $author$project$State$emptyAddTask,
			ak: '',
			aD: _List_Nil,
			L: false,
			w: $elm$core$Maybe$Nothing,
			cB: $elm$core$Maybe$Nothing,
			cC: $elm$core$Maybe$Nothing,
			aF: $elm$core$Maybe$Nothing,
			n: $author$project$State$emptyClientForm,
			aG: '',
			am: _List_Nil,
			an: $elm$core$Maybe$Nothing,
			bz: $elm$json$Json$Encode$null,
			cD: $elm$core$Dict$empty,
			cE: '',
			bA: $elm$core$Dict$empty,
			ao: false,
			x: $elm$core$Maybe$Nothing,
			N: $author$project$State$emptyEditLeadFrom,
			a5: false,
			cQ: 'All',
			cR: 'All',
			cS: 'All',
			Y: $elm$core$Dict$empty,
			aq: false,
			aM: $elm$json$Json$Encode$null,
			bH: '',
			cT: $elm$core$Dict$empty,
			a6: $elm$json$Json$Encode$null,
			a7: '',
			Z: function () {
				var _v0 = $author$project$State$routeOf(url);
				if (_v0.$ === 4) {
					var cid = _v0.a;
					return 'client:' + $elm$core$String$fromInt(cid);
				} else {
					return '';
				}
			}(),
			bb: 'tasks',
			q: key,
			P: _List_Nil,
			as: 0,
			C: false,
			bc: '',
			s: '',
			bT: A2(
				$elm$core$String$startsWith,
				'reset=',
				A2($elm$core$Maybe$withDefault, '', url.dd)) ? 'reset' : 'login',
			aQ: '',
			at: '',
			G: '',
			aS: '',
			aT: false,
			bY: _List_Nil,
			j: '',
			c7: true,
			c8: 0,
			R: $elm$core$Maybe$Nothing,
			aU: $elm$core$Maybe$Nothing,
			c9: $elm$json$Json$Encode$null,
			da: '',
			db: $elm$core$Maybe$Nothing,
			aV: '',
			aW: '',
			ac: '',
			dc: '',
			u: $elm$json$Json$Encode$null,
			v: $elm$core$Set$empty,
			bn: false,
			au: false,
			bo: false,
			aY: false,
			af: false,
			dl: true,
			dm: 'name',
			dq: $elm$core$Maybe$Nothing,
			J: _List_Nil,
			ce: 0,
			aZ: _List_Nil,
			cf: '',
			du: $elm$core$Maybe$Nothing,
			a_: url,
			a$: $elm$core$Maybe$Nothing,
			aB: 0,
			B: $author$project$State$emptyUserForm,
			T: _List_Nil
		};
	});
var $elm$core$Platform$Cmd$none = $elm$core$Platform$Cmd$batch(_List_Nil);
var $elm$time$Time$Name = function (a) {
	return {$: 0, a: a};
};
var $elm$time$Time$Offset = function (a) {
	return {$: 1, a: a};
};
var $elm$time$Time$Zone = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$time$Time$customZone = $elm$time$Time$Zone;
var $elm$time$Time$Posix = $elm$core$Basics$identity;
var $elm$time$Time$millisToPosix = $elm$core$Basics$identity;
var $elm$time$Time$now = _Time_now($elm$time$Time$millisToPosix);
var $elm$http$Http$BadStatus_ = F2(
	function (a, b) {
		return {$: 3, a: a, b: b};
	});
var $elm$http$Http$BadUrl_ = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$GoodStatus_ = F2(
	function (a, b) {
		return {$: 4, a: a, b: b};
	});
var $elm$http$Http$NetworkError_ = {$: 2};
var $elm$http$Http$Receiving = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$Sending = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$Timeout_ = {$: 1};
var $elm$core$Maybe$isJust = function (maybe) {
	if (!maybe.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Platform$sendToSelf = _Platform_sendToSelf;
var $elm$http$Http$emptyBody = _Http_emptyBody;
var $elm$http$Http$BadBody = function (a) {
	return {$: 4, a: a};
};
var $elm$http$Http$BadStatus = function (a) {
	return {$: 3, a: a};
};
var $elm$http$Http$BadUrl = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$NetworkError = {$: 2};
var $elm$http$Http$Timeout = {$: 1};
var $elm$core$Basics$composeR = F3(
	function (f, g, x) {
		return g(
			f(x));
	});
var $elm$json$Json$Decode$decodeString = _Json_runOnString;
var $elm$http$Http$expectStringResponse = F2(
	function (toMsg, toResult) {
		return A3(
			_Http_expect,
			'',
			$elm$core$Basics$identity,
			A2($elm$core$Basics$composeR, toResult, toMsg));
	});
var $elm$json$Json$Decode$field = _Json_decodeField;
var $elm$core$Result$mapError = F2(
	function (f, result) {
		if (!result.$) {
			var v = result.a;
			return $elm$core$Result$Ok(v);
		} else {
			var e = result.a;
			return $elm$core$Result$Err(
				f(e));
		}
	});
var $elm$json$Json$Decode$string = _Json_decodeString;
var $elm$core$Result$withDefault = F2(
	function (def, result) {
		if (!result.$) {
			var a = result.a;
			return a;
		} else {
			return def;
		}
	});
var $author$project$Api$expectJson = F2(
	function (toMsg, decoder) {
		return A2(
			$elm$http$Http$expectStringResponse,
			toMsg,
			function (response) {
				switch (response.$) {
					case 0:
						var url = response.a;
						return $elm$core$Result$Err(
							$elm$http$Http$BadUrl(url));
					case 1:
						return $elm$core$Result$Err($elm$http$Http$Timeout);
					case 2:
						return $elm$core$Result$Err($elm$http$Http$NetworkError);
					case 3:
						var metadata = response.a;
						var body = response.b;
						return (metadata.av === 401) ? $elm$core$Result$Err(
							$elm$http$Http$BadStatus(401)) : $elm$core$Result$Err(
							$elm$http$Http$BadBody(
								A2(
									$elm$core$Result$withDefault,
									'Request failed (' + ($elm$core$String$fromInt(metadata.av) + ')'),
									A2(
										$elm$json$Json$Decode$decodeString,
										A2($elm$json$Json$Decode$field, 'error', $elm$json$Json$Decode$string),
										body))));
					default:
						var body = response.b;
						return A2(
							$elm$core$Result$mapError,
							A2($elm$core$Basics$composeR, $elm$json$Json$Decode$errorToString, $elm$http$Http$BadBody),
							A2($elm$json$Json$Decode$decodeString, decoder, body));
				}
			});
	});
var $elm$http$Http$Request = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$State = F2(
	function (reqs, subs) {
		return {b5: reqs, cc: subs};
	});
var $elm$http$Http$init = $elm$core$Task$succeed(
	A2($elm$http$Http$State, $elm$core$Dict$empty, _List_Nil));
var $elm$core$Process$kill = _Scheduler_kill;
var $elm$core$Process$spawn = _Scheduler_spawn;
var $elm$http$Http$updateReqs = F3(
	function (router, cmds, reqs) {
		updateReqs:
		while (true) {
			if (!cmds.b) {
				return $elm$core$Task$succeed(reqs);
			} else {
				var cmd = cmds.a;
				var otherCmds = cmds.b;
				if (!cmd.$) {
					var tracker = cmd.a;
					var _v2 = A2($elm$core$Dict$get, tracker, reqs);
					if (_v2.$ === 1) {
						var $temp$router = router,
							$temp$cmds = otherCmds,
							$temp$reqs = reqs;
						router = $temp$router;
						cmds = $temp$cmds;
						reqs = $temp$reqs;
						continue updateReqs;
					} else {
						var pid = _v2.a;
						return A2(
							$elm$core$Task$andThen,
							function (_v3) {
								return A3(
									$elm$http$Http$updateReqs,
									router,
									otherCmds,
									A2($elm$core$Dict$remove, tracker, reqs));
							},
							$elm$core$Process$kill(pid));
					}
				} else {
					var req = cmd.a;
					return A2(
						$elm$core$Task$andThen,
						function (pid) {
							var _v4 = req.bs;
							if (_v4.$ === 1) {
								return A3($elm$http$Http$updateReqs, router, otherCmds, reqs);
							} else {
								var tracker = _v4.a;
								return A3(
									$elm$http$Http$updateReqs,
									router,
									otherCmds,
									A3($elm$core$Dict$insert, tracker, pid, reqs));
							}
						},
						$elm$core$Process$spawn(
							A3(
								_Http_toTask,
								router,
								$elm$core$Platform$sendToApp(router),
								req)));
				}
			}
		}
	});
var $elm$http$Http$onEffects = F4(
	function (router, cmds, subs, state) {
		return A2(
			$elm$core$Task$andThen,
			function (reqs) {
				return $elm$core$Task$succeed(
					A2($elm$http$Http$State, reqs, subs));
			},
			A3($elm$http$Http$updateReqs, router, cmds, state.b5));
	});
var $elm$core$List$maybeCons = F3(
	function (f, mx, xs) {
		var _v0 = f(mx);
		if (!_v0.$) {
			var x = _v0.a;
			return A2($elm$core$List$cons, x, xs);
		} else {
			return xs;
		}
	});
var $elm$core$List$filterMap = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$foldr,
			$elm$core$List$maybeCons(f),
			_List_Nil,
			xs);
	});
var $elm$http$Http$maybeSend = F4(
	function (router, desiredTracker, progress, _v0) {
		var actualTracker = _v0.a;
		var toMsg = _v0.b;
		return _Utils_eq(desiredTracker, actualTracker) ? $elm$core$Maybe$Just(
			A2(
				$elm$core$Platform$sendToApp,
				router,
				toMsg(progress))) : $elm$core$Maybe$Nothing;
	});
var $elm$http$Http$onSelfMsg = F3(
	function (router, _v0, state) {
		var tracker = _v0.a;
		var progress = _v0.b;
		return A2(
			$elm$core$Task$andThen,
			function (_v1) {
				return $elm$core$Task$succeed(state);
			},
			$elm$core$Task$sequence(
				A2(
					$elm$core$List$filterMap,
					A3($elm$http$Http$maybeSend, router, tracker, progress),
					state.cc)));
	});
var $elm$http$Http$Cancel = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$cmdMap = F2(
	function (func, cmd) {
		if (!cmd.$) {
			var tracker = cmd.a;
			return $elm$http$Http$Cancel(tracker);
		} else {
			var r = cmd.a;
			return $elm$http$Http$Request(
				{
					cr: r.cr,
					aE: r.aE,
					aL: A2(_Http_mapExpect, func, r.aL),
					a8: r.a8,
					be: r.be,
					br: r.br,
					bs: r.bs,
					a_: r.a_
				});
		}
	});
var $elm$http$Http$MySub = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$http$Http$subMap = F2(
	function (func, _v0) {
		var tracker = _v0.a;
		var toMsg = _v0.b;
		return A2(
			$elm$http$Http$MySub,
			tracker,
			A2($elm$core$Basics$composeR, toMsg, func));
	});
_Platform_effectManagers['Http'] = _Platform_createManager($elm$http$Http$init, $elm$http$Http$onEffects, $elm$http$Http$onSelfMsg, $elm$http$Http$cmdMap, $elm$http$Http$subMap);
var $elm$http$Http$command = _Platform_leaf('Http');
var $elm$http$Http$subscription = _Platform_leaf('Http');
var $elm$http$Http$request = function (r) {
	return $elm$http$Http$command(
		$elm$http$Http$Request(
			{cr: false, aE: r.aE, aL: r.aL, a8: r.a8, be: r.be, br: r.br, bs: r.bs, a_: r.a_}));
};
var $author$project$Api$authedRequest = F6(
	function (ctx, method, path, body, decoder, toMsg) {
		return $elm$http$Http$request(
			{
				aE: A2($elm$core$Maybe$withDefault, $elm$http$Http$emptyBody, body),
				aL: A2($author$project$Api$expectJson, toMsg, decoder),
				a8: _List_Nil,
				be: method,
				br: $elm$core$Maybe$Just(30000),
				bs: $elm$core$Maybe$Nothing,
				a_: _Utils_ap(ctx.M, path)
			});
	});
var $elm$json$Json$Decode$value = _Json_decodeValue;
var $author$project$Api$portalGet = function (ctx) {
	return A5($author$project$Api$authedRequest, ctx, 'GET', '/api/portal', $elm$core$Maybe$Nothing, $elm$json$Json$Decode$value);
};
var $justinmimbs$date$Date$RD = $elm$core$Basics$identity;
var $elm$core$Basics$clamp = F3(
	function (low, high, number) {
		return (_Utils_cmp(number, low) < 0) ? low : ((_Utils_cmp(number, high) > 0) ? high : number);
	});
var $elm$core$Basics$modBy = _Basics_modBy;
var $elm$core$Basics$neq = _Utils_notEqual;
var $justinmimbs$date$Date$isLeapYear = function (y) {
	return ((!A2($elm$core$Basics$modBy, 4, y)) && (!(!A2($elm$core$Basics$modBy, 100, y)))) || (!A2($elm$core$Basics$modBy, 400, y));
};
var $justinmimbs$date$Date$daysBeforeMonth = F2(
	function (y, m) {
		var leapDays = $justinmimbs$date$Date$isLeapYear(y) ? 1 : 0;
		switch (m) {
			case 0:
				return 0;
			case 1:
				return 31;
			case 2:
				return 59 + leapDays;
			case 3:
				return 90 + leapDays;
			case 4:
				return 120 + leapDays;
			case 5:
				return 151 + leapDays;
			case 6:
				return 181 + leapDays;
			case 7:
				return 212 + leapDays;
			case 8:
				return 243 + leapDays;
			case 9:
				return 273 + leapDays;
			case 10:
				return 304 + leapDays;
			default:
				return 334 + leapDays;
		}
	});
var $justinmimbs$date$Date$floorDiv = F2(
	function (a, b) {
		return $elm$core$Basics$floor(a / b);
	});
var $justinmimbs$date$Date$daysBeforeYear = function (y1) {
	var y = y1 - 1;
	var leapYears = (A2($justinmimbs$date$Date$floorDiv, y, 4) - A2($justinmimbs$date$Date$floorDiv, y, 100)) + A2($justinmimbs$date$Date$floorDiv, y, 400);
	return (365 * y) + leapYears;
};
var $justinmimbs$date$Date$daysInMonth = F2(
	function (y, m) {
		switch (m) {
			case 0:
				return 31;
			case 1:
				return $justinmimbs$date$Date$isLeapYear(y) ? 29 : 28;
			case 2:
				return 31;
			case 3:
				return 30;
			case 4:
				return 31;
			case 5:
				return 30;
			case 6:
				return 31;
			case 7:
				return 31;
			case 8:
				return 30;
			case 9:
				return 31;
			case 10:
				return 30;
			default:
				return 31;
		}
	});
var $justinmimbs$date$Date$fromCalendarDate = F3(
	function (y, m, d) {
		return ($justinmimbs$date$Date$daysBeforeYear(y) + A2($justinmimbs$date$Date$daysBeforeMonth, y, m)) + A3(
			$elm$core$Basics$clamp,
			1,
			A2($justinmimbs$date$Date$daysInMonth, y, m),
			d);
	});
var $elm$time$Time$flooredDiv = F2(
	function (numerator, denominator) {
		return $elm$core$Basics$floor(numerator / denominator);
	});
var $elm$time$Time$posixToMillis = function (_v0) {
	var millis = _v0;
	return millis;
};
var $elm$time$Time$toAdjustedMinutesHelp = F3(
	function (defaultOffset, posixMinutes, eras) {
		toAdjustedMinutesHelp:
		while (true) {
			if (!eras.b) {
				return posixMinutes + defaultOffset;
			} else {
				var era = eras.a;
				var olderEras = eras.b;
				if (_Utils_cmp(era.bp, posixMinutes) < 0) {
					return posixMinutes + era.b;
				} else {
					var $temp$defaultOffset = defaultOffset,
						$temp$posixMinutes = posixMinutes,
						$temp$eras = olderEras;
					defaultOffset = $temp$defaultOffset;
					posixMinutes = $temp$posixMinutes;
					eras = $temp$eras;
					continue toAdjustedMinutesHelp;
				}
			}
		}
	});
var $elm$time$Time$toAdjustedMinutes = F2(
	function (_v0, time) {
		var defaultOffset = _v0.a;
		var eras = _v0.b;
		return A3(
			$elm$time$Time$toAdjustedMinutesHelp,
			defaultOffset,
			A2(
				$elm$time$Time$flooredDiv,
				$elm$time$Time$posixToMillis(time),
				60000),
			eras);
	});
var $elm$core$Basics$ge = _Utils_ge;
var $elm$core$Basics$negate = function (n) {
	return -n;
};
var $elm$time$Time$toCivil = function (minutes) {
	var rawDay = A2($elm$time$Time$flooredDiv, minutes, 60 * 24) + 719468;
	var era = (((rawDay >= 0) ? rawDay : (rawDay - 146096)) / 146097) | 0;
	var dayOfEra = rawDay - (era * 146097);
	var yearOfEra = ((((dayOfEra - ((dayOfEra / 1460) | 0)) + ((dayOfEra / 36524) | 0)) - ((dayOfEra / 146096) | 0)) / 365) | 0;
	var dayOfYear = dayOfEra - (((365 * yearOfEra) + ((yearOfEra / 4) | 0)) - ((yearOfEra / 100) | 0));
	var mp = (((5 * dayOfYear) + 2) / 153) | 0;
	var month = mp + ((mp < 10) ? 3 : (-9));
	var year = yearOfEra + (era * 400);
	return {
		bB: (dayOfYear - ((((153 * mp) + 2) / 5) | 0)) + 1,
		bU: month,
		co: year + ((month <= 2) ? 1 : 0)
	};
};
var $elm$time$Time$toDay = F2(
	function (zone, time) {
		return $elm$time$Time$toCivil(
			A2($elm$time$Time$toAdjustedMinutes, zone, time)).bB;
	});
var $elm$time$Time$Apr = 3;
var $elm$time$Time$Aug = 7;
var $elm$time$Time$Dec = 11;
var $elm$time$Time$Feb = 1;
var $elm$time$Time$Jan = 0;
var $elm$time$Time$Jul = 6;
var $elm$time$Time$Jun = 5;
var $elm$time$Time$Mar = 2;
var $elm$time$Time$May = 4;
var $elm$time$Time$Nov = 10;
var $elm$time$Time$Oct = 9;
var $elm$time$Time$Sep = 8;
var $elm$time$Time$toMonth = F2(
	function (zone, time) {
		var _v0 = $elm$time$Time$toCivil(
			A2($elm$time$Time$toAdjustedMinutes, zone, time)).bU;
		switch (_v0) {
			case 1:
				return 0;
			case 2:
				return 1;
			case 3:
				return 2;
			case 4:
				return 3;
			case 5:
				return 4;
			case 6:
				return 5;
			case 7:
				return 6;
			case 8:
				return 7;
			case 9:
				return 8;
			case 10:
				return 9;
			case 11:
				return 10;
			default:
				return 11;
		}
	});
var $elm$time$Time$toYear = F2(
	function (zone, time) {
		return $elm$time$Time$toCivil(
			A2($elm$time$Time$toAdjustedMinutes, zone, time)).co;
	});
var $justinmimbs$date$Date$fromPosix = F2(
	function (zone, posix) {
		return A3(
			$justinmimbs$date$Date$fromCalendarDate,
			A2($elm$time$Time$toYear, zone, posix),
			A2($elm$time$Time$toMonth, zone, posix),
			A2($elm$time$Time$toDay, zone, posix));
	});
var $justinmimbs$date$Date$monthToNumber = function (m) {
	switch (m) {
		case 0:
			return 1;
		case 1:
			return 2;
		case 2:
			return 3;
		case 3:
			return 4;
		case 4:
			return 5;
		case 5:
			return 6;
		case 6:
			return 7;
		case 7:
			return 8;
		case 8:
			return 9;
		case 9:
			return 10;
		case 10:
			return 11;
		default:
			return 12;
	}
};
var $justinmimbs$date$Date$numberToMonth = function (mn) {
	var _v0 = A2($elm$core$Basics$max, 1, mn);
	switch (_v0) {
		case 1:
			return 0;
		case 2:
			return 1;
		case 3:
			return 2;
		case 4:
			return 3;
		case 5:
			return 4;
		case 6:
			return 5;
		case 7:
			return 6;
		case 8:
			return 7;
		case 9:
			return 8;
		case 10:
			return 9;
		case 11:
			return 10;
		default:
			return 11;
	}
};
var $justinmimbs$date$Date$toCalendarDateHelp = F3(
	function (y, m, d) {
		toCalendarDateHelp:
		while (true) {
			var monthDays = A2($justinmimbs$date$Date$daysInMonth, y, m);
			var mn = $justinmimbs$date$Date$monthToNumber(m);
			if ((mn < 12) && (_Utils_cmp(d, monthDays) > 0)) {
				var $temp$y = y,
					$temp$m = $justinmimbs$date$Date$numberToMonth(mn + 1),
					$temp$d = d - monthDays;
				y = $temp$y;
				m = $temp$m;
				d = $temp$d;
				continue toCalendarDateHelp;
			} else {
				return {bB: d, bU: m, co: y};
			}
		}
	});
var $justinmimbs$date$Date$divWithRemainder = F2(
	function (a, b) {
		return _Utils_Tuple2(
			A2($justinmimbs$date$Date$floorDiv, a, b),
			A2($elm$core$Basics$modBy, b, a));
	});
var $justinmimbs$date$Date$year = function (_v0) {
	var rd = _v0;
	var _v1 = A2($justinmimbs$date$Date$divWithRemainder, rd, 146097);
	var n400 = _v1.a;
	var r400 = _v1.b;
	var _v2 = A2($justinmimbs$date$Date$divWithRemainder, r400, 36524);
	var n100 = _v2.a;
	var r100 = _v2.b;
	var _v3 = A2($justinmimbs$date$Date$divWithRemainder, r100, 1461);
	var n4 = _v3.a;
	var r4 = _v3.b;
	var _v4 = A2($justinmimbs$date$Date$divWithRemainder, r4, 365);
	var n1 = _v4.a;
	var r1 = _v4.b;
	var n = (!r1) ? 0 : 1;
	return ((((n400 * 400) + (n100 * 100)) + (n4 * 4)) + n1) + n;
};
var $justinmimbs$date$Date$toOrdinalDate = function (_v0) {
	var rd = _v0;
	var y = $justinmimbs$date$Date$year(rd);
	return {
		bj: rd - $justinmimbs$date$Date$daysBeforeYear(y),
		co: y
	};
};
var $justinmimbs$date$Date$toCalendarDate = function (_v0) {
	var rd = _v0;
	var date = $justinmimbs$date$Date$toOrdinalDate(rd);
	return A3($justinmimbs$date$Date$toCalendarDateHelp, date.co, 0, date.bj);
};
var $justinmimbs$date$Date$day = A2(
	$elm$core$Basics$composeR,
	$justinmimbs$date$Date$toCalendarDate,
	function ($) {
		return $.bB;
	});
var $justinmimbs$date$Date$month = A2(
	$elm$core$Basics$composeR,
	$justinmimbs$date$Date$toCalendarDate,
	function ($) {
		return $.bU;
	});
var $justinmimbs$date$Date$monthNumber = A2($elm$core$Basics$composeR, $justinmimbs$date$Date$month, $justinmimbs$date$Date$monthToNumber);
var $justinmimbs$date$Date$ordinalDay = A2(
	$elm$core$Basics$composeR,
	$justinmimbs$date$Date$toOrdinalDate,
	function ($) {
		return $.bj;
	});
var $elm$core$String$cons = _String_cons;
var $elm$core$String$fromChar = function (_char) {
	return A2($elm$core$String$cons, _char, '');
};
var $elm$core$Bitwise$and = _Bitwise_and;
var $elm$core$Bitwise$shiftRightBy = _Bitwise_shiftRightBy;
var $elm$core$String$repeatHelp = F3(
	function (n, chunk, result) {
		return (n <= 0) ? result : A3(
			$elm$core$String$repeatHelp,
			n >> 1,
			_Utils_ap(chunk, chunk),
			(!(n & 1)) ? result : _Utils_ap(result, chunk));
	});
var $elm$core$String$repeat = F2(
	function (n, chunk) {
		return A3($elm$core$String$repeatHelp, n, chunk, '');
	});
var $elm$core$String$padLeft = F3(
	function (n, _char, string) {
		return _Utils_ap(
			A2(
				$elm$core$String$repeat,
				n - $elm$core$String$length(string),
				$elm$core$String$fromChar(_char)),
			string);
	});
var $elm$core$Basics$abs = function (n) {
	return (n < 0) ? (-n) : n;
};
var $justinmimbs$date$Date$padSignedInt = F2(
	function (length, _int) {
		return _Utils_ap(
			(_int < 0) ? '-' : '',
			A3(
				$elm$core$String$padLeft,
				length,
				'0',
				$elm$core$String$fromInt(
					$elm$core$Basics$abs(_int))));
	});
var $justinmimbs$date$Date$monthToQuarter = function (m) {
	return (($justinmimbs$date$Date$monthToNumber(m) + 2) / 3) | 0;
};
var $justinmimbs$date$Date$quarter = A2($elm$core$Basics$composeR, $justinmimbs$date$Date$month, $justinmimbs$date$Date$monthToQuarter);
var $elm$core$String$right = F2(
	function (n, string) {
		return (n < 1) ? '' : A3(
			$elm$core$String$slice,
			-n,
			$elm$core$String$length(string),
			string);
	});
var $justinmimbs$date$Date$weekdayNumber = function (_v0) {
	var rd = _v0;
	var _v1 = A2($elm$core$Basics$modBy, 7, rd);
	if (!_v1) {
		return 7;
	} else {
		var n = _v1;
		return n;
	}
};
var $justinmimbs$date$Date$daysBeforeWeekYear = function (y) {
	var jan4 = $justinmimbs$date$Date$daysBeforeYear(y) + 4;
	return jan4 - $justinmimbs$date$Date$weekdayNumber(jan4);
};
var $elm$time$Time$Fri = 4;
var $elm$time$Time$Mon = 0;
var $elm$time$Time$Sat = 5;
var $elm$time$Time$Sun = 6;
var $elm$time$Time$Thu = 3;
var $elm$time$Time$Tue = 1;
var $elm$time$Time$Wed = 2;
var $justinmimbs$date$Date$numberToWeekday = function (wdn) {
	var _v0 = A2($elm$core$Basics$max, 1, wdn);
	switch (_v0) {
		case 1:
			return 0;
		case 2:
			return 1;
		case 3:
			return 2;
		case 4:
			return 3;
		case 5:
			return 4;
		case 6:
			return 5;
		default:
			return 6;
	}
};
var $justinmimbs$date$Date$toWeekDate = function (_v0) {
	var rd = _v0;
	var wdn = $justinmimbs$date$Date$weekdayNumber(rd);
	var wy = $justinmimbs$date$Date$year(rd + (4 - wdn));
	var week1Day1 = $justinmimbs$date$Date$daysBeforeWeekYear(wy) + 1;
	return {
		cj: 1 + (((rd - week1Day1) / 7) | 0),
		ck: wy,
		dC: $justinmimbs$date$Date$numberToWeekday(wdn)
	};
};
var $justinmimbs$date$Date$weekNumber = A2(
	$elm$core$Basics$composeR,
	$justinmimbs$date$Date$toWeekDate,
	function ($) {
		return $.cj;
	});
var $justinmimbs$date$Date$weekYear = A2(
	$elm$core$Basics$composeR,
	$justinmimbs$date$Date$toWeekDate,
	function ($) {
		return $.ck;
	});
var $justinmimbs$date$Date$weekday = A2($elm$core$Basics$composeR, $justinmimbs$date$Date$weekdayNumber, $justinmimbs$date$Date$numberToWeekday);
var $elm$core$Basics$min = F2(
	function (x, y) {
		return (_Utils_cmp(x, y) < 0) ? x : y;
	});
var $justinmimbs$date$Date$ordinalSuffix = function (n) {
	var nn = A2($elm$core$Basics$modBy, 100, n);
	var _v0 = A2(
		$elm$core$Basics$min,
		(nn < 20) ? nn : A2($elm$core$Basics$modBy, 10, nn),
		4);
	switch (_v0) {
		case 1:
			return 'st';
		case 2:
			return 'nd';
		case 3:
			return 'rd';
		default:
			return 'th';
	}
};
var $justinmimbs$date$Date$withOrdinalSuffix = function (n) {
	return _Utils_ap(
		$elm$core$String$fromInt(n),
		$justinmimbs$date$Date$ordinalSuffix(n));
};
var $justinmimbs$date$Date$formatField = F4(
	function (language, _char, length, date) {
		switch (_char) {
			case 'y':
				if (length === 2) {
					return A2(
						$elm$core$String$right,
						2,
						A3(
							$elm$core$String$padLeft,
							2,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$year(date))));
				} else {
					return A2(
						$justinmimbs$date$Date$padSignedInt,
						length,
						$justinmimbs$date$Date$year(date));
				}
			case 'Y':
				if (length === 2) {
					return A2(
						$elm$core$String$right,
						2,
						A3(
							$elm$core$String$padLeft,
							2,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$weekYear(date))));
				} else {
					return A2(
						$justinmimbs$date$Date$padSignedInt,
						length,
						$justinmimbs$date$Date$weekYear(date));
				}
			case 'Q':
				switch (length) {
					case 1:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$quarter(date));
					case 2:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$quarter(date));
					case 3:
						return 'Q' + $elm$core$String$fromInt(
							$justinmimbs$date$Date$quarter(date));
					case 4:
						return $justinmimbs$date$Date$withOrdinalSuffix(
							$justinmimbs$date$Date$quarter(date));
					case 5:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$quarter(date));
					default:
						return '';
				}
			case 'M':
				switch (length) {
					case 1:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$monthNumber(date));
					case 2:
						return A3(
							$elm$core$String$padLeft,
							2,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$monthNumber(date)));
					case 3:
						return language.aR(
							$justinmimbs$date$Date$month(date));
					case 4:
						return language.bg(
							$justinmimbs$date$Date$month(date));
					case 5:
						return A2(
							$elm$core$String$left,
							1,
							language.aR(
								$justinmimbs$date$Date$month(date)));
					default:
						return '';
				}
			case 'w':
				switch (length) {
					case 1:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$weekNumber(date));
					case 2:
						return A3(
							$elm$core$String$padLeft,
							2,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$weekNumber(date)));
					default:
						return '';
				}
			case 'd':
				switch (length) {
					case 1:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$day(date));
					case 2:
						return A3(
							$elm$core$String$padLeft,
							2,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$day(date)));
					case 3:
						return language.a3(
							$justinmimbs$date$Date$day(date));
					default:
						return '';
				}
			case 'D':
				switch (length) {
					case 1:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$ordinalDay(date));
					case 2:
						return A3(
							$elm$core$String$padLeft,
							2,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$ordinalDay(date)));
					case 3:
						return A3(
							$elm$core$String$padLeft,
							3,
							'0',
							$elm$core$String$fromInt(
								$justinmimbs$date$Date$ordinalDay(date)));
					default:
						return '';
				}
			case 'E':
				switch (length) {
					case 1:
						return language.V(
							$justinmimbs$date$Date$weekday(date));
					case 2:
						return language.V(
							$justinmimbs$date$Date$weekday(date));
					case 3:
						return language.V(
							$justinmimbs$date$Date$weekday(date));
					case 4:
						return language.bt(
							$justinmimbs$date$Date$weekday(date));
					case 5:
						return A2(
							$elm$core$String$left,
							1,
							language.V(
								$justinmimbs$date$Date$weekday(date)));
					case 6:
						return A2(
							$elm$core$String$left,
							2,
							language.V(
								$justinmimbs$date$Date$weekday(date)));
					default:
						return '';
				}
			case 'e':
				switch (length) {
					case 1:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$weekdayNumber(date));
					case 2:
						return $elm$core$String$fromInt(
							$justinmimbs$date$Date$weekdayNumber(date));
					default:
						return A4($justinmimbs$date$Date$formatField, language, 'E', length, date);
				}
			default:
				return '';
		}
	});
var $justinmimbs$date$Date$formatWithTokens = F3(
	function (language, tokens, date) {
		return A3(
			$elm$core$List$foldl,
			F2(
				function (token, formatted) {
					if (!token.$) {
						var _char = token.a;
						var length = token.b;
						return _Utils_ap(
							A4($justinmimbs$date$Date$formatField, language, _char, length, date),
							formatted);
					} else {
						var str = token.a;
						return _Utils_ap(str, formatted);
					}
				}),
			'',
			tokens);
	});
var $justinmimbs$date$Pattern$Literal = function (a) {
	return {$: 1, a: a};
};
var $elm$parser$Parser$Advanced$Bad = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $elm$parser$Parser$Advanced$Good = F3(
	function (a, b, c) {
		return {$: 0, a: a, b: b, c: c};
	});
var $elm$parser$Parser$Advanced$Parser = $elm$core$Basics$identity;
var $elm$parser$Parser$Advanced$andThen = F2(
	function (callback, _v0) {
		var parseA = _v0;
		return function (s0) {
			var _v1 = parseA(s0);
			if (_v1.$ === 1) {
				var p = _v1.a;
				var x = _v1.b;
				return A2($elm$parser$Parser$Advanced$Bad, p, x);
			} else {
				var p1 = _v1.a;
				var a = _v1.b;
				var s1 = _v1.c;
				var _v2 = callback(a);
				var parseB = _v2;
				var _v3 = parseB(s1);
				if (_v3.$ === 1) {
					var p2 = _v3.a;
					var x = _v3.b;
					return A2($elm$parser$Parser$Advanced$Bad, p1 || p2, x);
				} else {
					var p2 = _v3.a;
					var b = _v3.b;
					var s2 = _v3.c;
					return A3($elm$parser$Parser$Advanced$Good, p1 || p2, b, s2);
				}
			}
		};
	});
var $elm$parser$Parser$andThen = $elm$parser$Parser$Advanced$andThen;
var $elm$parser$Parser$Advanced$map2 = F3(
	function (func, _v0, _v1) {
		var parseA = _v0;
		var parseB = _v1;
		return function (s0) {
			var _v2 = parseA(s0);
			if (_v2.$ === 1) {
				var p = _v2.a;
				var x = _v2.b;
				return A2($elm$parser$Parser$Advanced$Bad, p, x);
			} else {
				var p1 = _v2.a;
				var a = _v2.b;
				var s1 = _v2.c;
				var _v3 = parseB(s1);
				if (_v3.$ === 1) {
					var p2 = _v3.a;
					var x = _v3.b;
					return A2($elm$parser$Parser$Advanced$Bad, p1 || p2, x);
				} else {
					var p2 = _v3.a;
					var b = _v3.b;
					var s2 = _v3.c;
					return A3(
						$elm$parser$Parser$Advanced$Good,
						p1 || p2,
						A2(func, a, b),
						s2);
				}
			}
		};
	});
var $elm$parser$Parser$Advanced$ignorer = F2(
	function (keepParser, ignoreParser) {
		return A3($elm$parser$Parser$Advanced$map2, $elm$core$Basics$always, keepParser, ignoreParser);
	});
var $elm$parser$Parser$ignorer = $elm$parser$Parser$Advanced$ignorer;
var $elm$parser$Parser$Advanced$succeed = function (a) {
	return function (s) {
		return A3($elm$parser$Parser$Advanced$Good, false, a, s);
	};
};
var $elm$parser$Parser$succeed = $elm$parser$Parser$Advanced$succeed;
var $elm$parser$Parser$Expecting = function (a) {
	return {$: 0, a: a};
};
var $elm$parser$Parser$Advanced$Token = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$parser$Parser$toToken = function (str) {
	return A2(
		$elm$parser$Parser$Advanced$Token,
		str,
		$elm$parser$Parser$Expecting(str));
};
var $elm$parser$Parser$Advanced$AddRight = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $elm$parser$Parser$Advanced$DeadEnd = F4(
	function (row, col, problem, contextStack) {
		return {by: col, cG: contextStack, b0: problem, dh: row};
	});
var $elm$parser$Parser$Advanced$Empty = {$: 0};
var $elm$parser$Parser$Advanced$fromState = F2(
	function (s, x) {
		return A2(
			$elm$parser$Parser$Advanced$AddRight,
			$elm$parser$Parser$Advanced$Empty,
			A4($elm$parser$Parser$Advanced$DeadEnd, s.dh, s.by, x, s.c));
	});
var $elm$parser$Parser$Advanced$isSubString = _Parser_isSubString;
var $elm$core$Basics$not = _Basics_not;
var $elm$parser$Parser$Advanced$token = function (_v0) {
	var str = _v0.a;
	var expecting = _v0.b;
	var progress = !$elm$core$String$isEmpty(str);
	return function (s) {
		var _v1 = A5($elm$parser$Parser$Advanced$isSubString, str, s.b, s.dh, s.by, s.a);
		var newOffset = _v1.a;
		var newRow = _v1.b;
		var newCol = _v1.c;
		return _Utils_eq(newOffset, -1) ? A2(
			$elm$parser$Parser$Advanced$Bad,
			false,
			A2($elm$parser$Parser$Advanced$fromState, s, expecting)) : A3(
			$elm$parser$Parser$Advanced$Good,
			progress,
			0,
			{by: newCol, c: s.c, d: s.d, b: newOffset, dh: newRow, a: s.a});
	};
};
var $elm$parser$Parser$token = function (str) {
	return $elm$parser$Parser$Advanced$token(
		$elm$parser$Parser$toToken(str));
};
var $justinmimbs$date$Pattern$escapedQuote = A2(
	$elm$parser$Parser$ignorer,
	$elm$parser$Parser$succeed(
		$justinmimbs$date$Pattern$Literal('\'')),
	$elm$parser$Parser$token('\'\''));
var $elm$parser$Parser$UnexpectedChar = {$: 11};
var $elm$parser$Parser$Advanced$isSubChar = _Parser_isSubChar;
var $elm$parser$Parser$Advanced$chompIf = F2(
	function (isGood, expecting) {
		return function (s) {
			var newOffset = A3($elm$parser$Parser$Advanced$isSubChar, isGood, s.b, s.a);
			return _Utils_eq(newOffset, -1) ? A2(
				$elm$parser$Parser$Advanced$Bad,
				false,
				A2($elm$parser$Parser$Advanced$fromState, s, expecting)) : (_Utils_eq(newOffset, -2) ? A3(
				$elm$parser$Parser$Advanced$Good,
				true,
				0,
				{by: 1, c: s.c, d: s.d, b: s.b + 1, dh: s.dh + 1, a: s.a}) : A3(
				$elm$parser$Parser$Advanced$Good,
				true,
				0,
				{by: s.by + 1, c: s.c, d: s.d, b: newOffset, dh: s.dh, a: s.a}));
		};
	});
var $elm$parser$Parser$chompIf = function (isGood) {
	return A2($elm$parser$Parser$Advanced$chompIf, isGood, $elm$parser$Parser$UnexpectedChar);
};
var $justinmimbs$date$Pattern$Field = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$parser$Parser$Advanced$chompWhileHelp = F5(
	function (isGood, offset, row, col, s0) {
		chompWhileHelp:
		while (true) {
			var newOffset = A3($elm$parser$Parser$Advanced$isSubChar, isGood, offset, s0.a);
			if (_Utils_eq(newOffset, -1)) {
				return A3(
					$elm$parser$Parser$Advanced$Good,
					_Utils_cmp(s0.b, offset) < 0,
					0,
					{by: col, c: s0.c, d: s0.d, b: offset, dh: row, a: s0.a});
			} else {
				if (_Utils_eq(newOffset, -2)) {
					var $temp$isGood = isGood,
						$temp$offset = offset + 1,
						$temp$row = row + 1,
						$temp$col = 1,
						$temp$s0 = s0;
					isGood = $temp$isGood;
					offset = $temp$offset;
					row = $temp$row;
					col = $temp$col;
					s0 = $temp$s0;
					continue chompWhileHelp;
				} else {
					var $temp$isGood = isGood,
						$temp$offset = newOffset,
						$temp$row = row,
						$temp$col = col + 1,
						$temp$s0 = s0;
					isGood = $temp$isGood;
					offset = $temp$offset;
					row = $temp$row;
					col = $temp$col;
					s0 = $temp$s0;
					continue chompWhileHelp;
				}
			}
		}
	});
var $elm$parser$Parser$Advanced$chompWhile = function (isGood) {
	return function (s) {
		return A5($elm$parser$Parser$Advanced$chompWhileHelp, isGood, s.b, s.dh, s.by, s);
	};
};
var $elm$parser$Parser$chompWhile = $elm$parser$Parser$Advanced$chompWhile;
var $elm$parser$Parser$Advanced$getOffset = function (s) {
	return A3($elm$parser$Parser$Advanced$Good, false, s.b, s);
};
var $elm$parser$Parser$getOffset = $elm$parser$Parser$Advanced$getOffset;
var $elm$parser$Parser$Advanced$keeper = F2(
	function (parseFunc, parseArg) {
		return A3($elm$parser$Parser$Advanced$map2, $elm$core$Basics$apL, parseFunc, parseArg);
	});
var $elm$parser$Parser$keeper = $elm$parser$Parser$Advanced$keeper;
var $elm$parser$Parser$Problem = function (a) {
	return {$: 12, a: a};
};
var $elm$parser$Parser$Advanced$problem = function (x) {
	return function (s) {
		return A2(
			$elm$parser$Parser$Advanced$Bad,
			false,
			A2($elm$parser$Parser$Advanced$fromState, s, x));
	};
};
var $elm$parser$Parser$problem = function (msg) {
	return $elm$parser$Parser$Advanced$problem(
		$elm$parser$Parser$Problem(msg));
};
var $elm$core$String$foldr = _String_foldr;
var $elm$core$String$toList = function (string) {
	return A3($elm$core$String$foldr, $elm$core$List$cons, _List_Nil, string);
};
var $justinmimbs$date$Pattern$fieldRepeats = function (str) {
	var _v0 = $elm$core$String$toList(str);
	if (_v0.b && (!_v0.b.b)) {
		var _char = _v0.a;
		return A2(
			$elm$parser$Parser$keeper,
			A2(
				$elm$parser$Parser$keeper,
				$elm$parser$Parser$succeed(
					F2(
						function (x, y) {
							return A2($justinmimbs$date$Pattern$Field, _char, 1 + (y - x));
						})),
				A2(
					$elm$parser$Parser$ignorer,
					$elm$parser$Parser$getOffset,
					$elm$parser$Parser$chompWhile(
						$elm$core$Basics$eq(_char)))),
			$elm$parser$Parser$getOffset);
	} else {
		return $elm$parser$Parser$problem('expected exactly one char');
	}
};
var $elm$parser$Parser$Advanced$mapChompedString = F2(
	function (func, _v0) {
		var parse = _v0;
		return function (s0) {
			var _v1 = parse(s0);
			if (_v1.$ === 1) {
				var p = _v1.a;
				var x = _v1.b;
				return A2($elm$parser$Parser$Advanced$Bad, p, x);
			} else {
				var p = _v1.a;
				var a = _v1.b;
				var s1 = _v1.c;
				return A3(
					$elm$parser$Parser$Advanced$Good,
					p,
					A2(
						func,
						A3($elm$core$String$slice, s0.b, s1.b, s0.a),
						a),
					s1);
			}
		};
	});
var $elm$parser$Parser$Advanced$getChompedString = function (parser) {
	return A2($elm$parser$Parser$Advanced$mapChompedString, $elm$core$Basics$always, parser);
};
var $elm$parser$Parser$getChompedString = $elm$parser$Parser$Advanced$getChompedString;
var $justinmimbs$date$Pattern$field = A2(
	$elm$parser$Parser$andThen,
	$justinmimbs$date$Pattern$fieldRepeats,
	$elm$parser$Parser$getChompedString(
		$elm$parser$Parser$chompIf($elm$core$Char$isAlpha)));
var $justinmimbs$date$Pattern$finalize = A2(
	$elm$core$List$foldl,
	F2(
		function (token, tokens) {
			var _v0 = _Utils_Tuple2(token, tokens);
			if (((_v0.a.$ === 1) && _v0.b.b) && (_v0.b.a.$ === 1)) {
				var x = _v0.a.a;
				var _v1 = _v0.b;
				var y = _v1.a.a;
				var rest = _v1.b;
				return A2(
					$elm$core$List$cons,
					$justinmimbs$date$Pattern$Literal(
						_Utils_ap(x, y)),
					rest);
			} else {
				return A2($elm$core$List$cons, token, tokens);
			}
		}),
	_List_Nil);
var $elm$parser$Parser$Advanced$lazy = function (thunk) {
	return function (s) {
		var _v0 = thunk(0);
		var parse = _v0;
		return parse(s);
	};
};
var $elm$parser$Parser$lazy = $elm$parser$Parser$Advanced$lazy;
var $justinmimbs$date$Pattern$isLiteralChar = function (_char) {
	return (_char !== '\'') && (!$elm$core$Char$isAlpha(_char));
};
var $elm$parser$Parser$Advanced$map = F2(
	function (func, _v0) {
		var parse = _v0;
		return function (s0) {
			var _v1 = parse(s0);
			if (!_v1.$) {
				var p = _v1.a;
				var a = _v1.b;
				var s1 = _v1.c;
				return A3(
					$elm$parser$Parser$Advanced$Good,
					p,
					func(a),
					s1);
			} else {
				var p = _v1.a;
				var x = _v1.b;
				return A2($elm$parser$Parser$Advanced$Bad, p, x);
			}
		};
	});
var $elm$parser$Parser$map = $elm$parser$Parser$Advanced$map;
var $justinmimbs$date$Pattern$literal = A2(
	$elm$parser$Parser$map,
	$justinmimbs$date$Pattern$Literal,
	$elm$parser$Parser$getChompedString(
		A2(
			$elm$parser$Parser$ignorer,
			A2(
				$elm$parser$Parser$ignorer,
				$elm$parser$Parser$succeed(0),
				$elm$parser$Parser$chompIf($justinmimbs$date$Pattern$isLiteralChar)),
			$elm$parser$Parser$chompWhile($justinmimbs$date$Pattern$isLiteralChar))));
var $elm$parser$Parser$Advanced$Append = F2(
	function (a, b) {
		return {$: 2, a: a, b: b};
	});
var $elm$parser$Parser$Advanced$oneOfHelp = F3(
	function (s0, bag, parsers) {
		oneOfHelp:
		while (true) {
			if (!parsers.b) {
				return A2($elm$parser$Parser$Advanced$Bad, false, bag);
			} else {
				var parse = parsers.a;
				var remainingParsers = parsers.b;
				var _v1 = parse(s0);
				if (!_v1.$) {
					var step = _v1;
					return step;
				} else {
					var step = _v1;
					var p = step.a;
					var x = step.b;
					if (p) {
						return step;
					} else {
						var $temp$s0 = s0,
							$temp$bag = A2($elm$parser$Parser$Advanced$Append, bag, x),
							$temp$parsers = remainingParsers;
						s0 = $temp$s0;
						bag = $temp$bag;
						parsers = $temp$parsers;
						continue oneOfHelp;
					}
				}
			}
		}
	});
var $elm$parser$Parser$Advanced$oneOf = function (parsers) {
	return function (s) {
		return A3($elm$parser$Parser$Advanced$oneOfHelp, s, $elm$parser$Parser$Advanced$Empty, parsers);
	};
};
var $elm$parser$Parser$oneOf = $elm$parser$Parser$Advanced$oneOf;
var $elm$parser$Parser$ExpectingEnd = {$: 10};
var $elm$parser$Parser$Advanced$end = function (x) {
	return function (s) {
		return _Utils_eq(
			$elm$core$String$length(s.a),
			s.b) ? A3($elm$parser$Parser$Advanced$Good, false, 0, s) : A2(
			$elm$parser$Parser$Advanced$Bad,
			false,
			A2($elm$parser$Parser$Advanced$fromState, s, x));
	};
};
var $elm$parser$Parser$end = $elm$parser$Parser$Advanced$end($elm$parser$Parser$ExpectingEnd);
var $justinmimbs$date$Pattern$quotedHelp = function (result) {
	return $elm$parser$Parser$oneOf(
		_List_fromArray(
			[
				A2(
				$elm$parser$Parser$andThen,
				function (str) {
					return $justinmimbs$date$Pattern$quotedHelp(
						_Utils_ap(result, str));
				},
				$elm$parser$Parser$getChompedString(
					A2(
						$elm$parser$Parser$ignorer,
						A2(
							$elm$parser$Parser$ignorer,
							$elm$parser$Parser$succeed(0),
							$elm$parser$Parser$chompIf(
								$elm$core$Basics$neq('\''))),
						$elm$parser$Parser$chompWhile(
							$elm$core$Basics$neq('\''))))),
				A2(
				$elm$parser$Parser$andThen,
				function (_v0) {
					return $justinmimbs$date$Pattern$quotedHelp(result + '\'');
				},
				$elm$parser$Parser$token('\'\'')),
				$elm$parser$Parser$succeed(result)
			]));
};
var $justinmimbs$date$Pattern$quoted = A2(
	$elm$parser$Parser$keeper,
	A2(
		$elm$parser$Parser$ignorer,
		$elm$parser$Parser$succeed($justinmimbs$date$Pattern$Literal),
		$elm$parser$Parser$chompIf(
			$elm$core$Basics$eq('\''))),
	A2(
		$elm$parser$Parser$ignorer,
		$justinmimbs$date$Pattern$quotedHelp(''),
		$elm$parser$Parser$oneOf(
			_List_fromArray(
				[
					$elm$parser$Parser$chompIf(
					$elm$core$Basics$eq('\'')),
					$elm$parser$Parser$end
				]))));
var $justinmimbs$date$Pattern$patternHelp = function (tokens) {
	return $elm$parser$Parser$oneOf(
		_List_fromArray(
			[
				A2(
				$elm$parser$Parser$andThen,
				function (token) {
					return $justinmimbs$date$Pattern$patternHelp(
						A2($elm$core$List$cons, token, tokens));
				},
				$elm$parser$Parser$oneOf(
					_List_fromArray(
						[$justinmimbs$date$Pattern$field, $justinmimbs$date$Pattern$literal, $justinmimbs$date$Pattern$escapedQuote, $justinmimbs$date$Pattern$quoted]))),
				$elm$parser$Parser$lazy(
				function (_v0) {
					return $elm$parser$Parser$succeed(
						$justinmimbs$date$Pattern$finalize(tokens));
				})
			]));
};
var $elm$parser$Parser$DeadEnd = F3(
	function (row, col, problem) {
		return {by: col, b0: problem, dh: row};
	});
var $elm$parser$Parser$problemToDeadEnd = function (p) {
	return A3($elm$parser$Parser$DeadEnd, p.dh, p.by, p.b0);
};
var $elm$parser$Parser$Advanced$bagToList = F2(
	function (bag, list) {
		bagToList:
		while (true) {
			switch (bag.$) {
				case 0:
					return list;
				case 1:
					var bag1 = bag.a;
					var x = bag.b;
					var $temp$bag = bag1,
						$temp$list = A2($elm$core$List$cons, x, list);
					bag = $temp$bag;
					list = $temp$list;
					continue bagToList;
				default:
					var bag1 = bag.a;
					var bag2 = bag.b;
					var $temp$bag = bag1,
						$temp$list = A2($elm$parser$Parser$Advanced$bagToList, bag2, list);
					bag = $temp$bag;
					list = $temp$list;
					continue bagToList;
			}
		}
	});
var $elm$parser$Parser$Advanced$run = F2(
	function (_v0, src) {
		var parse = _v0;
		var _v1 = parse(
			{by: 1, c: _List_Nil, d: 1, b: 0, dh: 1, a: src});
		if (!_v1.$) {
			var value = _v1.b;
			return $elm$core$Result$Ok(value);
		} else {
			var bag = _v1.b;
			return $elm$core$Result$Err(
				A2($elm$parser$Parser$Advanced$bagToList, bag, _List_Nil));
		}
	});
var $elm$parser$Parser$run = F2(
	function (parser, source) {
		var _v0 = A2($elm$parser$Parser$Advanced$run, parser, source);
		if (!_v0.$) {
			var a = _v0.a;
			return $elm$core$Result$Ok(a);
		} else {
			var problems = _v0.a;
			return $elm$core$Result$Err(
				A2($elm$core$List$map, $elm$parser$Parser$problemToDeadEnd, problems));
		}
	});
var $justinmimbs$date$Pattern$fromString = function (str) {
	return A2(
		$elm$core$Result$withDefault,
		_List_fromArray(
			[
				$justinmimbs$date$Pattern$Literal(str)
			]),
		A2(
			$elm$parser$Parser$run,
			$justinmimbs$date$Pattern$patternHelp(_List_Nil),
			str));
};
var $justinmimbs$date$Date$formatWithLanguage = F2(
	function (language, pattern) {
		var tokens = $elm$core$List$reverse(
			$justinmimbs$date$Pattern$fromString(pattern));
		return A2($justinmimbs$date$Date$formatWithTokens, language, tokens);
	});
var $justinmimbs$date$Date$monthToName = function (m) {
	switch (m) {
		case 0:
			return 'January';
		case 1:
			return 'February';
		case 2:
			return 'March';
		case 3:
			return 'April';
		case 4:
			return 'May';
		case 5:
			return 'June';
		case 6:
			return 'July';
		case 7:
			return 'August';
		case 8:
			return 'September';
		case 9:
			return 'October';
		case 10:
			return 'November';
		default:
			return 'December';
	}
};
var $justinmimbs$date$Date$weekdayToName = function (wd) {
	switch (wd) {
		case 0:
			return 'Monday';
		case 1:
			return 'Tuesday';
		case 2:
			return 'Wednesday';
		case 3:
			return 'Thursday';
		case 4:
			return 'Friday';
		case 5:
			return 'Saturday';
		default:
			return 'Sunday';
	}
};
var $justinmimbs$date$Date$language_en = {
	a3: $justinmimbs$date$Date$withOrdinalSuffix,
	bg: $justinmimbs$date$Date$monthToName,
	aR: A2(
		$elm$core$Basics$composeR,
		$justinmimbs$date$Date$monthToName,
		$elm$core$String$left(3)),
	bt: $justinmimbs$date$Date$weekdayToName,
	V: A2(
		$elm$core$Basics$composeR,
		$justinmimbs$date$Date$weekdayToName,
		$elm$core$String$left(3))
};
var $justinmimbs$date$Date$format = function (pattern) {
	return A2($justinmimbs$date$Date$formatWithLanguage, $justinmimbs$date$Date$language_en, pattern);
};
var $justinmimbs$date$Date$toIsoString = $justinmimbs$date$Date$format('yyyy-MM-dd');
var $elm$time$Time$utc = A2($elm$time$Time$Zone, 0, _List_Nil);
var $author$project$Main$toIsoDay = function (posix) {
	return $justinmimbs$date$Date$toIsoString(
		A2($justinmimbs$date$Date$fromPosix, $elm$time$Time$utc, posix));
};
var $author$project$Main$init = F3(
	function (_v0, url, key) {
		var proto = function () {
			var _v2 = url.b3;
			if (!_v2) {
				return 'http';
			} else {
				return 'https';
			}
		}();
		var base = $author$project$Api$computeBase(
			{bN: url.bN, b$: url.b$, b3: proto});
		return _Utils_Tuple2(
			function (m) {
				return _Utils_update(
					m,
					{
						ak: base,
						cT: $author$project$Features$defaults(
							A2($elm$core$String$dropLeft, 6, url.A))
					});
			}(
				A2($author$project$State$initialModel, key, url)),
			$elm$core$Platform$Cmd$batch(
				_List_fromArray(
					[
						A2(
						$elm$core$Task$perform,
						A2($elm$core$Basics$composeL, $author$project$State$TodayChanged, $author$project$Main$toIsoDay),
						$elm$time$Time$now),
						function () {
						if (url.A === '/portal') {
							var _v1 = url.bJ;
							if (!_v1.$) {
								var fragment = _v1.a;
								return A2(
									$elm$core$Task$perform,
									$elm$core$Basics$always(
										$author$project$State$PortalExchange(
											A2($elm$core$String$dropLeft, 6, fragment))),
									$elm$core$Task$succeed(0));
							} else {
								return A2(
									$author$project$Api$portalGet,
									{M: base, du: $elm$core$Maybe$Nothing},
									A2(
										$author$project$Main$acceptLoad,
										A2($author$project$State$initialModel, key, url),
										$author$project$State$PortalLoaded));
							}
						} else {
							return $elm$core$Platform$Cmd$none;
						}
					}()
					])));
	});
var $author$project$State$GotStoredDark = function (a) {
	return {$: 42, a: a};
};
var $author$project$State$GotStoredToken = function (a) {
	return {$: 41, a: a};
};
var $elm$core$Platform$Sub$batch = _Platform_batch;
var $elm$json$Json$Decode$bool = _Json_decodeBool;
var $author$project$Main$loadDark = _Platform_incomingPort('loadDark', $elm$json$Json$Decode$bool);
var $elm$json$Json$Decode$null = _Json_decodeNull;
var $elm$json$Json$Decode$oneOf = _Json_oneOf;
var $author$project$Main$loadToken = _Platform_incomingPort(
	'loadToken',
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$elm$json$Json$Decode$null($elm$core$Maybe$Nothing),
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$string)
			])));
var $author$project$Main$subscriptions = function (_v0) {
	return $elm$core$Platform$Sub$batch(
		_List_fromArray(
			[
				$author$project$Main$loadToken($author$project$State$GotStoredToken),
				$author$project$Main$loadDark($author$project$State$GotStoredDark)
			]));
};
var $author$project$State$AddLeadDone = function (a) {
	return {$: 62, a: a};
};
var $author$project$State$AddTaskDone = function (a) {
	return {$: 98, a: a};
};
var $author$project$State$AdvanceDone = function (a) {
	return {$: 70, a: a};
};
var $author$project$State$BulkDone = function (a) {
	return {$: 88, a: a};
};
var $author$project$State$CaseFormSaved = function (a) {
	return {$: 112, a: a};
};
var $author$project$State$ClientDocUploaded = function (a) {
	return {$: 120, a: a};
};
var $author$project$State$ClientFormSaved = function (a) {
	return {$: 104, a: a};
};
var $author$project$State$ClientUpdated = function (a) {
	return {$: 105, a: a};
};
var $author$project$State$ClientsLoaded = function (a) {
	return {$: 53, a: a};
};
var $author$project$State$ConvertDone = function (a) {
	return {$: 72, a: a};
};
var $author$project$State$DeleteCaseDone = function (a) {
	return {$: 114, a: a};
};
var $author$project$State$DeleteClientDone = function (a) {
	return {$: 107, a: a};
};
var $author$project$State$DeleteLeadDone = function (a) {
	return {$: 68, a: a};
};
var $author$project$State$DeleteUserDone = function (a) {
	return {$: 134, a: a};
};
var $author$project$State$DocDeleteDone = function (a) {
	return {$: 122, a: a};
};
var $author$project$State$EditLeadDone = function (a) {
	return {$: 66, a: a};
};
var $author$project$State$FeatureDone = function (a) {
	return {$: 29, a: a};
};
var $author$project$State$LeadDocUploaded = function (a) {
	return {$: 119, a: a};
};
var $author$project$State$LeadsImported = function (a) {
	return {$: 125, a: a};
};
var $author$project$State$LeadsLoaded = function (a) {
	return {$: 50, a: a};
};
var $author$project$State$LoginDone = function (a) {
	return {$: 47, a: a};
};
var $author$project$State$LogoutDone = function (a) {
	return {$: 9, a: a};
};
var $author$project$State$MeDone = function (a) {
	return {$: 48, a: a};
};
var $author$project$State$NoOp = {$: 38};
var $author$project$State$NoteDone = function (a) {
	return {$: 75, a: a};
};
var $author$project$State$OperationDone = function (a) {
	return {$: 14, a: a};
};
var $author$project$State$PasswordChangeDone = function (a) {
	return {$: 140, a: a};
};
var $author$project$State$PortalExchanged = function (a) {
	return {$: 32, a: a};
};
var $author$project$State$PortalUploaded = function (a) {
	return {$: 36, a: a};
};
var $author$project$State$RecoveryDone = function (a) {
	return {$: 7, a: a};
};
var $author$project$State$ResetDone = function (a) {
	return {$: 8, a: a};
};
var $author$project$State$SearchReady = F2(
	function (a, b) {
		return {$: 11, a: a, b: b};
	});
var $author$project$State$TaskDeleteDone = function (a) {
	return {$: 92, a: a};
};
var $author$project$State$TaskStatusDone = function (a) {
	return {$: 90, a: a};
};
var $author$project$State$UserSaved = function (a) {
	return {$: 131, a: a};
};
var $author$project$State$UserUpdatedDone = function (a) {
	return {$: 132, a: a};
};
var $elm$json$Json$Encode$object = function (pairs) {
	return _Json_wrap(
		A3(
			$elm$core$List$foldl,
			F2(
				function (_v0, obj) {
					var k = _v0.a;
					var v = _v0.b;
					return A3(_Json_addField, k, v, obj);
				}),
			_Json_emptyObject(0),
			pairs));
};
var $author$project$Types$encodeNote = function (note) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'nrNote',
				$elm$json$Json$Encode$string(note))
			]));
};
var $elm$json$Json$Decode$keyValuePairs = _Json_decodeKeyValuePairs;
var $elm$json$Json$Decode$dict = function (decoder) {
	return A2(
		$elm$json$Json$Decode$map,
		$elm$core$Dict$fromList,
		$elm$json$Json$Decode$keyValuePairs(decoder));
};
var $author$project$Api$ignoreDecoder = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			A2(
			$elm$json$Json$Decode$map,
			function (_v0) {
				return 0;
			},
			$elm$json$Json$Decode$dict($elm$json$Json$Decode$value)),
			$elm$json$Json$Decode$succeed(0)
		]));
var $elm$http$Http$jsonBody = function (value) {
	return A2(
		_Http_pair,
		'application/json',
		A2($elm$json$Json$Encode$encode, 0, value));
};
var $author$project$Api$addNote = F3(
	function (ctx, id, note) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/leads/' + ($elm$core$String$fromInt(id) + '/notes'),
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(
					$author$project$Types$encodeNote(note))),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Types$Lead = function (id) {
	return function (number) {
		return function (fullName) {
			return function (email) {
				return function (phone) {
					return function (source) {
						return function (consultantId) {
							return function (consultantName) {
								return function (quality) {
									return function (stage) {
										return function (destination) {
											return function (service) {
												return function (notes) {
													return function (lastContact) {
														return function (nextFollowup) {
															return function (createdAt) {
																return function (updatedAt) {
																	return function (revision) {
																		return {a2: consultantId, cF: consultantName, W: createdAt, aJ: destination, ap: email, bK: fullName, a9: id, aN: lastContact, _: nextFollowup, aa: notes, bV: number, bZ: phone, ad: quality, m: revision, ae: service, ah: source, $7: stage, dz: updatedAt};
																	};
																};
															};
														};
													};
												};
											};
										};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $author$project$Types$dateStr = $elm$json$Json$Decode$string;
var $elm$json$Json$Decode$int = _Json_decodeInt;
var $author$project$Types$maybeInt = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$int),
			$elm$json$Json$Decode$null($elm$core$Maybe$Nothing)
		]));
var $author$project$Types$maybeString = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$string),
			$elm$json$Json$Decode$null($elm$core$Maybe$Nothing)
		]));
var $elm$json$Json$Decode$nullable = function (decoder) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$elm$json$Json$Decode$null($elm$core$Maybe$Nothing),
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, decoder)
			]));
};
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom = $elm$json$Json$Decode$map2($elm$core$Basics$apR);
var $elm$json$Json$Decode$andThen = _Json_andThen;
var $elm$json$Json$Decode$at = F2(
	function (fields, decoder) {
		return A3($elm$core$List$foldr, $elm$json$Json$Decode$field, decoder, fields);
	});
var $elm$json$Json$Decode$decodeValue = _Json_run;
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optionalDecoder = F3(
	function (path, valDecoder, fallback) {
		var nullOr = function (decoder) {
			return $elm$json$Json$Decode$oneOf(
				_List_fromArray(
					[
						decoder,
						$elm$json$Json$Decode$null(fallback)
					]));
		};
		var handleResult = function (input) {
			var _v0 = A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$at, path, $elm$json$Json$Decode$value),
				input);
			if (!_v0.$) {
				var rawValue = _v0.a;
				var _v1 = A2(
					$elm$json$Json$Decode$decodeValue,
					nullOr(valDecoder),
					rawValue);
				if (!_v1.$) {
					var finalResult = _v1.a;
					return $elm$json$Json$Decode$succeed(finalResult);
				} else {
					return A2(
						$elm$json$Json$Decode$at,
						path,
						nullOr(valDecoder));
				}
			} else {
				return $elm$json$Json$Decode$succeed(fallback);
			}
		};
		return A2($elm$json$Json$Decode$andThen, handleResult, $elm$json$Json$Decode$value);
	});
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional = F4(
	function (key, valDecoder, fallback, decoder) {
		return A2(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optionalDecoder,
				_List_fromArray(
					[key]),
				valDecoder,
				fallback),
			decoder);
	});
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required = F3(
	function (key, valDecoder, decoder) {
		return A2(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom,
			A2($elm$json$Json$Decode$field, key, valDecoder),
			decoder);
	});
var $author$project$Types$leadDecoder = A4(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
	'revision',
	$elm$json$Json$Decode$int,
	1,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'updatedAt',
		$author$project$Types$dateStr,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'createdAt',
			$author$project$Types$dateStr,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'nextFollowup',
				$elm$json$Json$Decode$nullable($author$project$Types$dateStr),
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'lastContact',
					$elm$json$Json$Decode$nullable($author$project$Types$dateStr),
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'notes',
						$author$project$Types$maybeString,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'service',
							$author$project$Types$maybeString,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'destination',
								$author$project$Types$maybeString,
								A3(
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
									'stage',
									$elm$json$Json$Decode$string,
									A3(
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
										'quality',
										$author$project$Types$maybeString,
										A3(
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
											'consultantName',
											$author$project$Types$maybeString,
											A3(
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
												'consultantId',
												$author$project$Types$maybeInt,
												A3(
													$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
													'source',
													$author$project$Types$maybeString,
													A3(
														$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
														'phone',
														$author$project$Types$maybeString,
														A3(
															$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
															'email',
															$author$project$Types$maybeString,
															A3(
																$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
																'fullName',
																$elm$json$Json$Decode$string,
																A3(
																	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
																	'leadNumber',
																	$elm$json$Json$Decode$string,
																	A3(
																		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
																		'leadId',
																		$elm$json$Json$Decode$int,
																		$elm$json$Json$Decode$succeed($author$project$Types$Lead)))))))))))))))))));
var $author$project$Api$advanceLead = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/leads/' + ($elm$core$String$fromInt(id) + '/advance'),
			$elm$core$Maybe$Nothing,
			$author$project$Types$leadDecoder);
	});
var $elm$core$Maybe$andThen = F2(
	function (callback, maybeValue) {
		if (!maybeValue.$) {
			var value = maybeValue.a;
			return callback(value);
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $author$project$State$ConflictLoaded = function (a) {
	return {$: 20, a: a};
};
var $elm$url$Url$percentEncode = _Url_percentEncode;
var $author$project$Api$featureGet = F4(
	function (ctx, section, query, offset) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/workspace/' + (section + ('?q=' + ($elm$url$Url$percentEncode(query) + ('&offset=' + $elm$core$String$fromInt(offset))))),
			$elm$core$Maybe$Nothing,
			$elm$json$Json$Decode$value);
	});
var $elm$core$Dict$map = F2(
	function (func, dict) {
		if (dict.$ === -2) {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		} else {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				key,
				A2(func, key, value),
				A2($elm$core$Dict$map, func, left),
				A2($elm$core$Dict$map, func, right));
		}
	});
var $elm$core$Maybe$map = F2(
	function (f, maybe) {
		if (!maybe.$) {
			var value = maybe.a;
			return $elm$core$Maybe$Just(
				f(value));
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $elm$core$List$any = F2(
	function (isOkay, list) {
		any:
		while (true) {
			if (!list.b) {
				return false;
			} else {
				var x = list.a;
				var xs = list.b;
				if (isOkay(x)) {
					return true;
				} else {
					var $temp$isOkay = isOkay,
						$temp$list = xs;
					isOkay = $temp$isOkay;
					list = $temp$list;
					continue any;
				}
			}
		}
	});
var $elm$core$List$member = F2(
	function (x, xs) {
		return A2(
			$elm$core$List$any,
			function (a) {
				return _Utils_eq(a, x);
			},
			xs);
	});
var $elm$core$Tuple$pair = F2(
	function (a, b) {
		return _Utils_Tuple2(a, b);
	});
var $elm$json$Json$Decode$float = _Json_decodeFloat;
var $elm$core$String$fromFloat = _String_fromNumber;
var $author$project$Features$scalar = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			$elm$json$Json$Decode$string,
			A2($elm$json$Json$Decode$map, $elm$core$String$fromInt, $elm$json$Json$Decode$int),
			A2($elm$json$Json$Decode$map, $elm$core$String$fromFloat, $elm$json$Json$Decode$float),
			A2(
			$elm$json$Json$Decode$map,
			function (b) {
				return b ? 'true' : 'false';
			},
			$elm$json$Json$Decode$bool),
			$elm$json$Json$Decode$null('')
		]));
var $elm$core$Result$toMaybe = function (result) {
	if (!result.$) {
		var v = result.a;
		return $elm$core$Maybe$Just(v);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Features$formValues = function (row) {
	return A2(
		$elm$core$Dict$map,
		F2(
			function (key, value_) {
				return A2(
					$elm$core$List$member,
					key,
					_List_fromArray(
						['required', 'enabled', 'assignments', 'deadlines', 'documents', 'escalations', 'emailEnabled'])) ? ((value_ === '1') ? 'true' : ((value_ === '0') ? 'false' : value_)) : value_;
			}),
		$elm$core$Dict$fromList(
			A2(
				$elm$core$List$filterMap,
				function (_v0) {
					var key = _v0.a;
					var value = _v0.b;
					return A2(
						$elm$core$Maybe$map,
						$elm$core$Tuple$pair(key),
						$elm$core$Result$toMaybe(
							A2($elm$json$Json$Decode$decodeValue, $author$project$Features$scalar, value)));
				},
				A2(
					$elm$core$Result$withDefault,
					_List_Nil,
					A2(
						$elm$json$Json$Decode$decodeValue,
						$elm$json$Json$Decode$keyValuePairs($elm$json$Json$Decode$value),
						row)))));
};
var $author$project$Main$beginConflict = F5(
	function (model, kind, rid, original, edited) {
		return _Utils_Tuple2(
			_Utils_update(
				model,
				{
					bz: $elm$json$Json$Encode$null,
					cD: $author$project$Features$formValues(edited),
					cE: kind,
					bA: $author$project$Features$formValues(original)
				}),
			A5(
				$author$project$Api$featureGet,
				{M: model.ak, du: model.du},
				'conflict/' + (kind + ('/' + $elm$core$String$fromInt(rid))),
				'',
				0,
				A2($author$project$Main$acceptLoad, model, $author$project$State$ConflictLoaded)));
	});
var $elm$json$Json$Encode$int = _Json_wrap;
var $author$project$Types$encodeBulkRequest = function (b) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'brOp',
				$elm$json$Json$Encode$string(b.bi)),
				_Utils_Tuple2(
				'brIds',
				A2($elm$json$Json$Encode$list, $elm$json$Json$Encode$int, b.ba)),
				_Utils_Tuple2(
				'brConsultantId',
				A2(
					$elm$core$Maybe$withDefault,
					$elm$json$Json$Encode$null,
					A2($elm$core$Maybe$map, $elm$json$Json$Encode$int, b.a2)))
			]));
};
var $author$project$Api$bulkLeads = F2(
	function (ctx, spec) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/bulk/leads',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(
					$author$project$Types$encodeBulkRequest(spec))),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$State$caseFormOf = function (cr) {
	return {
		al: $elm$core$Maybe$Just(cr.a9),
		cy: A2($elm$core$Maybe$withDefault, 'Student Visa', cr.cy),
		aI: A2($elm$core$Maybe$withDefault, '', cr.aI),
		aJ: A2($elm$core$Maybe$withDefault, 'Canada', cr.aJ),
		m: cr.m,
		$7: cr.$7
	};
};
var $elm$core$String$trim = _String_trim;
var $author$project$Types$encodeNonEmpty = function (s) {
	return ($elm$core$String$trim(s) === '') ? $elm$json$Json$Encode$null : $elm$json$Json$Encode$string(s);
};
var $author$project$Types$maybeDate = function (s) {
	return ($elm$core$String$trim(s) === '') ? $elm$json$Json$Encode$null : $elm$json$Json$Encode$string(s);
};
var $author$project$Types$encodeCaseInput = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'ciServiceCategory',
				$author$project$Types$encodeNonEmpty(f.cy)),
				_Utils_Tuple2(
				'ciDestination',
				$author$project$Types$encodeNonEmpty(f.aJ)),
				_Utils_Tuple2(
				'ciStage',
				$author$project$Types$encodeNonEmpty(f.$7)),
				_Utils_Tuple2(
				'ciNextDeadline',
				$author$project$Types$maybeDate(f.aI)),
				_Utils_Tuple2(
				'ciCaseId',
				A2(
					$elm$core$Maybe$withDefault,
					$elm$json$Json$Encode$null,
					A2($elm$core$Maybe$map, $elm$json$Json$Encode$int, f.al)))
			]));
};
var $author$project$Main$casePayload = function (cf) {
	return $author$project$Types$encodeCaseInput(
		{al: cf.al, cy: cf.cy, aI: cf.aI, aJ: cf.aJ, $7: cf.$7});
};
var $author$project$Types$encodePasswordChange = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'pcCurrent',
				$elm$json$Json$Encode$string(f.cH)),
				_Utils_Tuple2(
				'pcNew',
				$elm$json$Json$Encode$string(f.c1))
			]));
};
var $author$project$Api$changePassword = F3(
	function (ctx, current, _new) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'PUT',
			'/api/auth/password',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(
					$author$project$Types$encodePasswordChange(
						{cH: current, c1: _new}))),
			$author$project$Api$ignoreDecoder);
	});
var $elm$http$Http$filePart = _Http_pair;
var $elm$http$Http$multipartBody = function (parts) {
	return A2(
		_Http_pair,
		'',
		_Http_toFormData(parts));
};
var $elm$http$Http$stringPart = _Http_pair;
var $author$project$Api$checklistUpload = F4(
	function (ctx, rid, revision, file) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/workspace/documents/' + ($elm$core$String$fromInt(rid) + '/upload'),
			$elm$core$Maybe$Just(
				$elm$http$Http$multipartBody(
					_List_fromArray(
						[
							A2($elm$http$Http$filePart, 'file', file),
							A2(
							$elm$http$Http$stringPart,
							'expectedRevision',
							$elm$core$String$fromInt(revision))
						]))),
			$elm$json$Json$Decode$value);
	});
var $author$project$State$clientFormOf = function (c) {
	return {
		ap: A2($elm$core$Maybe$withDefault, '', c.ap),
		bK: c.bK,
		bX: A2(
			$elm$core$Maybe$withDefault,
			'',
			A2($elm$core$Maybe$map, $elm$core$String$fromInt, c.cv)),
		bZ: A2($elm$core$Maybe$withDefault, '', c.bZ),
		m: c.m
	};
};
var $author$project$Types$encodeNewClient = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'ncFullName',
				$elm$json$Json$Encode$string(f.bK)),
				_Utils_Tuple2(
				'ncEmail',
				$author$project$Types$encodeNonEmpty(f.ap)),
				_Utils_Tuple2(
				'ncPhone',
				$author$project$Types$encodeNonEmpty(f.bZ)),
				_Utils_Tuple2(
				'ncCaseOfficer',
				A2(
					$elm$core$Maybe$withDefault,
					$elm$json$Json$Encode$null,
					A2($elm$core$Maybe$map, $elm$json$Json$Encode$int, f.bX)))
			]));
};
var $author$project$Main$withRevision = F2(
	function (revision, value) {
		return $elm$json$Json$Encode$object(
			A2(
				$elm$core$List$cons,
				_Utils_Tuple2(
					'expectedRevision',
					$elm$json$Json$Encode$int(revision)),
				A2(
					$elm$core$Result$withDefault,
					_List_Nil,
					A2(
						$elm$json$Json$Decode$decodeValue,
						$elm$json$Json$Decode$keyValuePairs($elm$json$Json$Decode$value),
						value))));
	});
var $author$project$Main$clientPayload = function (model) {
	return A2(
		$author$project$Main$withRevision,
		model.n.m,
		$author$project$Types$encodeNewClient(
			{
				ap: model.n.ap,
				bK: model.n.bK,
				bX: $elm$core$String$toInt(model.n.bX),
				bZ: model.n.bZ
			}));
};
var $author$project$Main$clientTaskBody = F2(
	function (model, cid) {
		var form = model.k;
		return $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2('ntLeadId', $elm$json$Json$Encode$null),
					_Utils_Tuple2(
					'ntClientId',
					$elm$json$Json$Encode$int(cid)),
					_Utils_Tuple2(
					'ntTitle',
					$elm$json$Json$Encode$string(form.ay)),
					_Utils_Tuple2(
					'ntDescription',
					$elm$json$Json$Encode$string(form.a4)),
					_Utils_Tuple2(
					'ntDueDate',
					(form.aK === '') ? $elm$json$Json$Encode$null : $elm$json$Json$Encode$string(form.aK)),
					_Utils_Tuple2(
					'ntPriority',
					$elm$json$Json$Encode$string(form.bl))
				]));
	});
var $author$project$Types$Client = F9(
	function (id, number, fullName, email, phone, caseOfficerId, caseOfficerName, createdAt, revision) {
		return {cv: caseOfficerId, cw: caseOfficerName, W: createdAt, ap: email, bK: fullName, a9: id, bV: number, bZ: phone, m: revision};
	});
var $author$project$Types$clientDecoder = A4(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
	'revision',
	$elm$json$Json$Decode$int,
	1,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'createdAt',
		$author$project$Types$dateStr,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'caseOfficerName',
			$author$project$Types$maybeString,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'caseOfficerId',
				$author$project$Types$maybeInt,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'phone',
					$author$project$Types$maybeString,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'email',
						$author$project$Types$maybeString,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'fullName',
							$elm$json$Json$Decode$string,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'number',
								$elm$json$Json$Decode$string,
								A3(
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
									'id',
									$elm$json$Json$Decode$int,
									$elm$json$Json$Decode$succeed($author$project$Types$Client))))))))));
var $author$project$Api$convertLead = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/leads/' + ($elm$core$String$fromInt(id) + '/convert'),
			$elm$core$Maybe$Nothing,
			$author$project$Types$clientDecoder);
	});
var $author$project$Api$createClient = F2(
	function (ctx, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/clients',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Types$clientDecoder);
	});
var $author$project$Api$createLead = F2(
	function (ctx, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/leads',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Types$leadDecoder);
	});
var $author$project$Types$Task = function (id) {
	return function (leadId) {
		return function (leadName) {
			return function (title) {
				return function (description) {
					return function (dueDate) {
						return function (priority) {
							return function (status) {
								return function (assignedTo) {
									return function (assigneeName) {
										return function (createdAt) {
											return function (clientId) {
												return function (revision) {
													return {ct: assignedTo, cu: assigneeName, a1: clientId, W: createdAt, a4: description, aK: dueDate, a9: id, aP: leadId, bS: leadName, bl: priority, m: revision, dr: status, ay: title};
												};
											};
										};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $author$project$Types$taskDecoder = A4(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
	'revision',
	$elm$json$Json$Decode$int,
	1,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'clientId',
		$author$project$Types$maybeInt,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'createdAt',
			$author$project$Types$dateStr,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'assigneeName',
				$author$project$Types$maybeString,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'assignedTo',
					$author$project$Types$maybeInt,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'status',
						$elm$json$Json$Decode$string,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'priority',
							$elm$json$Json$Decode$string,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'dueDate',
								$elm$json$Json$Decode$nullable($author$project$Types$dateStr),
								A3(
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
									'description',
									$author$project$Types$maybeString,
									A3(
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
										'title',
										$elm$json$Json$Decode$string,
										A3(
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
											'leadName',
											$author$project$Types$maybeString,
											A3(
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
												'leadId',
												$elm$json$Json$Decode$int,
												A3(
													$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
													'id',
													$elm$json$Json$Decode$int,
													$elm$json$Json$Decode$succeed($author$project$Types$Task))))))))))))));
var $author$project$Api$createTask = F2(
	function (ctx, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/tasks',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Types$taskDecoder);
	});
var $author$project$Types$User = F6(
	function (id, email, name, role, revision, mfaRequired) {
		return {ap: email, a9: id, bf: mfaRequired, t: name, m: revision, aX: role};
	});
var $author$project$Types$userDecoder = A4(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
	'mfaRequired',
	$elm$json$Json$Decode$bool,
	false,
	A4(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
		'revision',
		$elm$json$Json$Decode$int,
		1,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'role',
			$elm$json$Json$Decode$string,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'name',
				$elm$json$Json$Decode$string,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'email',
					$elm$json$Json$Decode$string,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'id',
						$elm$json$Json$Decode$int,
						$elm$json$Json$Decode$succeed($author$project$Types$User)))))));
var $author$project$Api$createUser = F2(
	function (ctx, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/users',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Types$userDecoder);
	});
var $author$project$Api$deleteCase = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'DELETE',
			'/api/cases/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$deleteClient = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'DELETE',
			'/api/clients/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$deleteDocument = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'DELETE',
			'/api/documents/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$deleteLead = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'DELETE',
			'/api/leads/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$deleteTask = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'DELETE',
			'/api/tasks/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$deleteUser = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'DELETE',
			'/api/users/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Api$ignoreDecoder);
	});
var $elm$core$Tuple$mapSecond = F2(
	function (func, _v0) {
		var x = _v0.a;
		var y = _v0.b;
		return _Utils_Tuple2(
			x,
			func(y));
	});
var $author$project$Main$dictValue = function (fields) {
	return $elm$json$Json$Encode$object(
		A2(
			$elm$core$List$map,
			$elm$core$Tuple$mapSecond($elm$json$Json$Encode$string),
			$elm$core$Dict$toList(fields)));
};
var $author$project$State$editLeadOf = function (l) {
	return {
		a2: l.a2,
		aJ: A2($elm$core$Maybe$withDefault, 'Canada', l.aJ),
		ap: A2($elm$core$Maybe$withDefault, '', l.ap),
		bK: l.bK,
		aN: A2($elm$core$Maybe$withDefault, '', l.aN),
		_: A2($elm$core$Maybe$withDefault, '', l._),
		aa: A2($elm$core$Maybe$withDefault, '', l.aa),
		bZ: A2($elm$core$Maybe$withDefault, '', l.bZ),
		ad: A2($elm$core$Maybe$withDefault, 'Warm', l.ad),
		m: l.m,
		ae: A2($elm$core$Maybe$withDefault, 'Student Visa', l.ae),
		ah: A2($elm$core$Maybe$withDefault, 'Website', l.ah),
		$7: l.$7
	};
};
var $author$project$State$emptyCaseForm = {al: $elm$core$Maybe$Nothing, cy: 'Student Visa', aI: '', aJ: 'Canada', m: 1, $7: 'Documents Under Review'};
var $author$project$Types$encodeNewLead = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'nlFullName',
				$elm$json$Json$Encode$string(f.bK)),
				_Utils_Tuple2(
				'nlEmail',
				$author$project$Types$encodeNonEmpty(f.ap)),
				_Utils_Tuple2(
				'nlPhone',
				$author$project$Types$encodeNonEmpty(f.bZ)),
				_Utils_Tuple2(
				'nlSource',
				$author$project$Types$encodeNonEmpty(f.ah)),
				_Utils_Tuple2(
				'nlQuality',
				$author$project$Types$encodeNonEmpty(f.ad)),
				_Utils_Tuple2(
				'nlStage',
				$author$project$Types$encodeNonEmpty(f.$7)),
				_Utils_Tuple2(
				'nlDestination',
				$author$project$Types$encodeNonEmpty(f.aJ)),
				_Utils_Tuple2(
				'nlService',
				$author$project$Types$encodeNonEmpty(f.ae)),
				_Utils_Tuple2(
				'nlNotes',
				$author$project$Types$encodeNonEmpty(f.aa)),
				_Utils_Tuple2(
				'nlNextFollowup',
				$author$project$Types$maybeDate(f._)),
				_Utils_Tuple2('nlConsultantId', $elm$json$Json$Encode$null)
			]));
};
var $author$project$Types$encodeNewUser = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'nuName',
				$elm$json$Json$Encode$string(f.t)),
				_Utils_Tuple2(
				'nuEmail',
				$elm$json$Json$Encode$string(f.ap)),
				_Utils_Tuple2(
				'nuRole',
				$elm$json$Json$Encode$string(f.aX)),
				_Utils_Tuple2(
				'nuPassword',
				$elm$json$Json$Encode$string(f.ab))
			]));
};
var $author$project$Types$encodeUpdateLead = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'expectedRevision',
				$elm$json$Json$Encode$int(f.m)),
				_Utils_Tuple2(
				'ulFullName',
				$author$project$Types$encodeNonEmpty(f.bK)),
				_Utils_Tuple2(
				'ulEmail',
				$author$project$Types$encodeNonEmpty(f.ap)),
				_Utils_Tuple2(
				'ulPhone',
				$author$project$Types$encodeNonEmpty(f.bZ)),
				_Utils_Tuple2(
				'ulSource',
				$author$project$Types$encodeNonEmpty(f.ah)),
				_Utils_Tuple2(
				'ulQuality',
				$author$project$Types$encodeNonEmpty(f.ad)),
				_Utils_Tuple2(
				'ulStage',
				$author$project$Types$encodeNonEmpty(f.$7)),
				_Utils_Tuple2(
				'ulDestination',
				$author$project$Types$encodeNonEmpty(f.aJ)),
				_Utils_Tuple2(
				'ulService',
				$author$project$Types$encodeNonEmpty(f.ae)),
				_Utils_Tuple2(
				'ulNotes',
				$author$project$Types$encodeNonEmpty(f.aa)),
				_Utils_Tuple2(
				'ulLastContact',
				$author$project$Types$maybeDate(f.aN)),
				_Utils_Tuple2(
				'ulNextFollowup',
				$author$project$Types$maybeDate(f._)),
				_Utils_Tuple2(
				'ulConsultantId',
				A2(
					$elm$core$Maybe$withDefault,
					$elm$json$Json$Encode$null,
					A2($elm$core$Maybe$map, $elm$json$Json$Encode$int, f.a2)))
			]));
};
var $author$project$Types$encodeUpdateUser = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'uuName',
				$elm$json$Json$Encode$string(f.t)),
				_Utils_Tuple2(
				'uuRole',
				$elm$json$Json$Encode$string(f.aX)),
				_Utils_Tuple2(
				'uuPassword',
				$author$project$Types$encodeNonEmpty(f.ab))
			]));
};
var $author$project$Main$expiredSession = function (msg) {
	_v0$13:
	while (true) {
		switch (msg.$) {
			case 20:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 29:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 15:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 50:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 53:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 52:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 55:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 54:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 56:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 12:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 14:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 51:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			case 57:
				if (((msg.a.$ === 1) && (msg.a.a.$ === 3)) && (msg.a.a.a === 401)) {
					return true;
				} else {
					break _v0$13;
				}
			default:
				break _v0$13;
		}
	}
	return false;
};
var $author$project$Api$featurePost = F3(
	function (ctx, path, value) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/workspace/' + path,
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(value)),
			$elm$json$Json$Decode$value);
	});
var $author$project$Main$featureSection = function (model) {
	var _v0 = $author$project$State$routeOf(model.a_);
	if (_v0.$ === 4) {
		return model.bb;
	} else {
		return A2($elm$core$String$dropLeft, 6, model.a_.A);
	}
};
var $elm$json$Json$Decode$list = _Json_decodeList;
var $author$project$Api$fetchClientsPage = F3(
	function (ctx, offset, query) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/clients?limit=50&offset=' + ($elm$core$String$fromInt(offset) + ('&q=' + $elm$url$Url$percentEncode(query))),
			$elm$core$Maybe$Nothing,
			$elm$json$Json$Decode$list($author$project$Types$clientDecoder));
	});
var $author$project$Api$fetchFilteredLeads = F3(
	function (ctx, filters, offset) {
		var pick = function (value) {
			return (value === 'All') ? '' : $elm$url$Url$percentEncode(value);
		};
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/leads?limit=50&offset=' + ($elm$core$String$fromInt(offset) + ('&q=' + ($elm$url$Url$percentEncode(filters.dc) + ('&stage=' + (pick(filters.cS) + ('&quality=' + (pick(filters.cQ) + ('&source=' + (pick(filters.cR) + ('&sort=' + ($elm$url$Url$percentEncode(filters.dm) + ('&direction=' + (filters.dl ? 'asc' : 'desc'))))))))))))),
			$elm$core$Maybe$Nothing,
			$elm$json$Json$Decode$list($author$project$Types$leadDecoder));
	});
var $elm$core$List$filter = F2(
	function (isGood, list) {
		return A3(
			$elm$core$List$foldr,
			F2(
				function (x, xs) {
					return isGood(x) ? A2($elm$core$List$cons, x, xs) : xs;
				}),
			_List_Nil,
			list);
	});
var $elm$core$List$sortWith = _List_sortWith;
var $elm$core$String$toLower = _String_toLower;
var $author$project$Views$filteredLeads = function (model) {
	var qLower = $elm$core$String$toLower(
		$elm$core$String$trim(model.dc));
	var matchesQ = function (l) {
		return (qLower === '') || (A2(
			$elm$core$String$contains,
			qLower,
			$elm$core$String$toLower(l.bK)) || (A2(
			$elm$core$Maybe$withDefault,
			false,
			A2(
				$elm$core$Maybe$map,
				function (e) {
					return A2(
						$elm$core$String$contains,
						qLower,
						$elm$core$String$toLower(e));
				},
				l.ap)) || (A2(
			$elm$core$Maybe$withDefault,
			false,
			A2(
				$elm$core$Maybe$map,
				function (p) {
					return A2(
						$elm$core$String$contains,
						qLower,
						$elm$core$String$toLower(p));
				},
				l.bZ)) || A2(
			$elm$core$String$contains,
			qLower,
			$elm$core$String$toLower(l.bV)))));
	};
	var matches = F2(
		function (f, val) {
			return (f === 'All') || _Utils_eq(
				$elm$core$Maybe$Just(val),
				$elm$core$Maybe$Just(f));
		});
	var keyOf = function (l) {
		var _v0 = model.dm;
		switch (_v0) {
			case 'stage':
				return $elm$core$String$toLower(l.$7);
			case 'quality':
				var _v1 = l.ad;
				_v1$3:
				while (true) {
					if (!_v1.$) {
						switch (_v1.a) {
							case 'Hot':
								return '0';
							case 'Warm':
								return '1';
							case 'Cold':
								return '2';
							default:
								break _v1$3;
						}
					} else {
						break _v1$3;
					}
				}
				return '3';
			case 'followup':
				return A2($elm$core$Maybe$withDefault, '9999', l._);
			default:
				return $elm$core$String$toLower(l.bK);
		}
	};
	var base = A2(
		$elm$core$List$filter,
		function (l) {
			return matchesQ(l) && (A2(matches, model.cS, l.$7) && (A2(
				matches,
				model.cQ,
				A2($elm$core$Maybe$withDefault, '', l.ad)) && A2(
				matches,
				model.cR,
				A2($elm$core$Maybe$withDefault, '', l.ah))));
		},
		model.P);
	return A2(
		$elm$core$List$sortWith,
		F2(
			function (a, b) {
				return model.dl ? A2(
					$elm$core$Basics$compare,
					keyOf(a),
					keyOf(b)) : A2(
					$elm$core$Basics$compare,
					keyOf(b),
					keyOf(a));
			}),
		base);
};
var $elm$core$Set$insert = F2(
	function (key, _v0) {
		var dict = _v0;
		return A3($elm$core$Dict$insert, key, 0, dict);
	});
var $elm$core$Set$fromList = function (list) {
	return A3($elm$core$List$foldl, $elm$core$Set$insert, $elm$core$Set$empty, list);
};
var $elm$core$List$head = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(x);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Main$httpError = function (err) {
	switch (err.$) {
		case 0:
			var url = err.a;
			return 'Bad URL: ' + url;
		case 1:
			return 'Request timed out';
		case 2:
			return 'Network error — is the API running?';
		case 3:
			var code = err.a;
			switch (code) {
				case 401:
					return 'Not authenticated — sign in again';
				case 403:
					return 'You don\'t have permission for that';
				case 404:
					return 'Not found';
				case 409:
					return 'This record or action changed. Refresh and review the latest version before trying again.';
				case 428:
					return 'Reload this record to obtain its current version before saving.';
				case 429:
					return 'Too many requests. Wait before trying again.';
				case 423:
					return 'File quarantined: wait for a successful malware scan. Infected files and failed scans stay blocked.';
				default:
					return 'Server error (' + ($elm$core$String$fromInt(code) + ')');
			}
		default:
			var body = err.a;
			return A2($elm$core$String$left, 240, body);
	}
};
var $author$project$Types$ImportResult = F2(
	function (imported, failed) {
		return {bG: failed, bO: imported};
	});
var $author$project$Types$ImportRowError = F2(
	function (row, error) {
		return {cO: error, dh: row};
	});
var $author$project$Types$importResultDecoder = A3(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
	'failed',
	$elm$json$Json$Decode$list(
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'error',
			$elm$json$Json$Decode$string,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'row',
				$elm$json$Json$Decode$int,
				$elm$json$Json$Decode$succeed($author$project$Types$ImportRowError)))),
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'imported',
		$elm$json$Json$Decode$int,
		$elm$json$Json$Decode$succeed($author$project$Types$ImportResult)));
var $author$project$Api$importLeads = F3(
	function (ctx, file, toMsg) {
		return $elm$http$Http$request(
			{
				aE: $elm$http$Http$multipartBody(
					_List_fromArray(
						[
							A2($elm$http$Http$filePart, 'file', file)
						])),
				aL: A2($author$project$Api$expectJson, toMsg, $author$project$Types$importResultDecoder),
				a8: _List_Nil,
				be: 'POST',
				br: $elm$core$Maybe$Just(30000),
				bs: $elm$core$Maybe$Nothing,
				a_: ctx.M + '/api/import/leads'
			});
	});
var $author$project$Main$justOf = function (r) {
	return $elm$core$Result$toMaybe(r);
};
var $elm$browser$Browser$Navigation$load = _Browser_load;
var $author$project$Types$LoginResponse = F2(
	function (token, user) {
		return {du: token, a$: user};
	});
var $author$project$Types$loginResponseDecoder = A3(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
	'user',
	$author$project$Types$userDecoder,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'token',
		$elm$json$Json$Decode$string,
		$elm$json$Json$Decode$succeed($author$project$Types$LoginResponse)));
var $elm$http$Http$post = function (r) {
	return $elm$http$Http$request(
		{aE: r.aE, aL: r.aL, a8: _List_Nil, be: 'POST', br: $elm$core$Maybe$Nothing, bs: $elm$core$Maybe$Nothing, a_: r.a_});
};
var $author$project$Api$login = F5(
	function (ctx, email, password, otp, toMsg) {
		return $elm$http$Http$post(
			{
				aE: $elm$http$Http$jsonBody(
					$elm$json$Json$Encode$object(
						_List_fromArray(
							[
								_Utils_Tuple2(
								'lrEmail',
								$elm$json$Json$Encode$string(email)),
								_Utils_Tuple2(
								'lrPassword',
								$elm$json$Json$Encode$string(password)),
								_Utils_Tuple2(
								'lrOtp',
								$elm$json$Json$Encode$string(otp))
							]))),
				aL: A2($author$project$Api$expectJson, toMsg, $author$project$Types$loginResponseDecoder),
				a_: ctx.M + '/api/auth/login'
			});
	});
var $author$project$Api$logout = function (ctx) {
	return A5($author$project$Api$authedRequest, ctx, 'POST', '/api/auth/logout', $elm$core$Maybe$Nothing, $author$project$Api$ignoreDecoder);
};
var $author$project$Api$me = F2(
	function (ctx, toMsg) {
		return A6($author$project$Api$authedRequest, ctx, 'GET', '/api/auth/me', $elm$core$Maybe$Nothing, $author$project$Types$userDecoder, toMsg);
	});
var $elm$browser$Browser$Navigation$pushUrl = _Browser_pushUrl;
var $author$project$Main$navigateTo = F2(
	function (key, path) {
		return A2($elm$browser$Browser$Navigation$pushUrl, key, path);
	});
var $author$project$Api$operation = F2(
	function (ctx, path) {
		return A5($author$project$Api$authedRequest, ctx, 'POST', '/api/' + path, $elm$core$Maybe$Nothing, $author$project$Api$ignoreDecoder);
	});
var $author$project$Main$ownerForUrl = function (url) {
	var _v0 = $author$project$State$routeOf(url);
	if (_v0.$ === 4) {
		var cid = _v0.a;
		return 'client:' + $elm$core$String$fromInt(cid);
	} else {
		return '';
	}
};
var $author$project$Api$portalPost = F3(
	function (ctx, action, value) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/portal/' + action,
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(value)),
			$elm$json$Json$Decode$value);
	});
var $author$project$Api$portalUpload = F3(
	function (ctx, rid, file) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/portal/requests/' + ($elm$core$String$fromInt(rid) + '/upload'),
			$elm$core$Maybe$Just(
				$elm$http$Http$multipartBody(
					_List_fromArray(
						[
							A2($elm$http$Http$filePart, 'file', file)
						]))),
			$elm$json$Json$Decode$value);
	});
var $author$project$State$ToastExpired = function (a) {
	return {$: 146, a: a};
};
var $elm$core$Process$sleep = _Process_sleep;
var $author$project$Main$pushToast = F3(
	function (model, kind, textMsg) {
		var id = model.ce + 1;
		var newToast = {a9: id, c_: kind, c0: textMsg};
		return _Utils_Tuple2(
			_Utils_update(
				model,
				{
					ce: id,
					aZ: _Utils_ap(
						model.aZ,
						_List_fromArray(
							[newToast]))
				}),
			A2(
				$elm$core$Task$perform,
				$elm$core$Basics$always(
					$author$project$State$ToastExpired(id)),
				$elm$core$Process$sleep(3500)));
	});
var $author$project$Api$recover = F2(
	function (ctx, email) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/auth/recover',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(
					$elm$json$Json$Encode$object(
						_List_fromArray(
							[
								_Utils_Tuple2(
								'email',
								$elm$json$Json$Encode$string(email))
							])))),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$State$AuditLoaded = function (a) {
	return {$: 57, a: a};
};
var $author$project$State$ClientDetailLoaded = function (a) {
	return {$: 54, a: a};
};
var $author$project$State$DetailLoaded = function (a) {
	return {$: 55, a: a};
};
var $author$project$State$FeatureLoaded = function (a) {
	return {$: 15, a: a};
};
var $author$project$State$OperationsLoaded = function (a) {
	return {$: 12, a: a};
};
var $author$project$State$StatsLoaded = function (a) {
	return {$: 56, a: a};
};
var $author$project$State$TasksLoaded = function (a) {
	return {$: 52, a: a};
};
var $author$project$State$UsersLoaded = function (a) {
	return {$: 51, a: a};
};
var $author$project$Types$AuditEntry = F8(
	function (id, entityType, entityId, entityName, action, changes, actorName, createdAt) {
		return {cp: action, cq: actorName, cA: changes, W: createdAt, cL: entityId, cM: entityName, cN: entityType, a9: id};
	});
var $author$project$Types$auditDecoder = A3(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
	'createdAt',
	$author$project$Types$dateStr,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'actorName',
		$author$project$Types$maybeString,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'changes',
			$elm$json$Json$Decode$nullable($elm$json$Json$Decode$value),
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'action',
				$elm$json$Json$Decode$string,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'entityName',
					$author$project$Types$maybeString,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'entityId',
						$elm$json$Json$Decode$int,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'entityType',
							$elm$json$Json$Decode$string,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'id',
								$elm$json$Json$Decode$int,
								$elm$json$Json$Decode$succeed($author$project$Types$AuditEntry)))))))));
var $author$project$Api$fetchAudit = F2(
	function (ctx, limit) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/audit?limit=' + $elm$core$String$fromInt(limit),
			$elm$core$Maybe$Nothing,
			$elm$json$Json$Decode$list($author$project$Types$auditDecoder));
	});
var $author$project$Types$ClientDetail = F5(
	function (client, cases, documents, tasks, activities) {
		return {bu: activities, cx: cases, a0: client, bC: documents, J: tasks};
	});
var $author$project$Types$Activity = F6(
	function (id, leadId, leadName, kind, description, date) {
		return {cI: date, a4: description, a9: id, c_: kind, aP: leadId, bS: leadName};
	});
var $author$project$Types$activityDecoder = A3(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
	'date',
	$author$project$Types$dateStr,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'description',
		$author$project$Types$maybeString,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'kind',
			$elm$json$Json$Decode$string,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'leadName',
				$author$project$Types$maybeString,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'leadId',
					$elm$json$Json$Decode$int,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'id',
						$elm$json$Json$Decode$int,
						$elm$json$Json$Decode$succeed($author$project$Types$Activity)))))));
var $author$project$Types$CaseRow = F8(
	function (id, clientId, category, destination, stage, deadline, createdAt, revision) {
		return {cy: category, a1: clientId, W: createdAt, aI: deadline, aJ: destination, a9: id, m: revision, $7: stage};
	});
var $author$project$Types$caseDecoder = A4(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
	'revision',
	$elm$json$Json$Decode$int,
	1,
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'createdAt',
		$author$project$Types$dateStr,
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'deadline',
			$elm$json$Json$Decode$nullable($author$project$Types$dateStr),
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'stage',
				$elm$json$Json$Decode$string,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'destination',
					$author$project$Types$maybeString,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'category',
						$author$project$Types$maybeString,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'clientId',
							$elm$json$Json$Decode$int,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'id',
								$elm$json$Json$Decode$int,
								$elm$json$Json$Decode$succeed($author$project$Types$CaseRow)))))))));
var $author$project$Types$Document = function (id) {
	return function (leadId) {
		return function (clientId) {
			return function (filename) {
				return function (mimeType) {
					return function (size) {
						return function (uploaderName) {
							return function (createdAt) {
								return function (scanStatus) {
									return function (revision) {
										return {a1: clientId, W: createdAt, cU: filename, a9: id, aP: leadId, c$: mimeType, m: revision, di: scanStatus, dk: size, dA: uploaderName};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $author$project$Types$documentDecoder = A4(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
	'revision',
	$elm$json$Json$Decode$int,
	1,
	A4(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional,
		'scanStatus',
		$elm$json$Json$Decode$string,
		'Pending',
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'createdAt',
			$author$project$Types$dateStr,
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'uploader',
				$author$project$Types$maybeString,
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'size',
					$elm$json$Json$Decode$int,
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'mimeType',
						$elm$json$Json$Decode$string,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'filename',
							$elm$json$Json$Decode$string,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'clientId',
								$author$project$Types$maybeInt,
								A3(
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
									'leadId',
									$author$project$Types$maybeInt,
									A3(
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
										'id',
										$elm$json$Json$Decode$int,
										$elm$json$Json$Decode$succeed($author$project$Types$Document)))))))))));
var $author$project$Types$clientDetailDecoder = A3(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
	'activities',
	$elm$json$Json$Decode$list($author$project$Types$activityDecoder),
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'tasks',
		$elm$json$Json$Decode$list($author$project$Types$taskDecoder),
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'documents',
			$elm$json$Json$Decode$list($author$project$Types$documentDecoder),
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'cases',
				$elm$json$Json$Decode$list($author$project$Types$caseDecoder),
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'client',
					$author$project$Types$clientDecoder,
					$elm$json$Json$Decode$succeed($author$project$Types$ClientDetail))))));
var $author$project$Api$fetchClientDetail = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/clients/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Types$clientDetailDecoder);
	});
var $author$project$Api$fetchClients = function (ctx) {
	return A5(
		$author$project$Api$authedRequest,
		ctx,
		'GET',
		'/api/clients',
		$elm$core$Maybe$Nothing,
		$elm$json$Json$Decode$list($author$project$Types$clientDecoder));
};
var $author$project$Types$LeadDetail = F4(
	function (lead, tasks, activities, documents) {
		return {bu: activities, bC: documents, aO: lead, J: tasks};
	});
var $author$project$Types$leadDetailDecoder = A3(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
	'documents',
	$elm$json$Json$Decode$list($author$project$Types$documentDecoder),
	A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'activities',
		$elm$json$Json$Decode$list($author$project$Types$activityDecoder),
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'tasks',
			$elm$json$Json$Decode$list($author$project$Types$taskDecoder),
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'lead',
				$author$project$Types$leadDecoder,
				$elm$json$Json$Decode$succeed($author$project$Types$LeadDetail)))));
var $author$project$Api$fetchLeadDetail = F2(
	function (ctx, id) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/leads/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Nothing,
			$author$project$Types$leadDetailDecoder);
	});
var $author$project$Api$fetchLeads = function (ctx) {
	return A5(
		$author$project$Api$authedRequest,
		ctx,
		'GET',
		'/api/leads',
		$elm$core$Maybe$Nothing,
		$elm$json$Json$Decode$list($author$project$Types$leadDecoder));
};
var $author$project$Api$fetchOperations = F3(
	function (ctx, kind, offset) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/' + (kind + ('?limit=50&offset=' + $elm$core$String$fromInt(offset))),
			$elm$core$Maybe$Nothing,
			$elm$json$Json$Decode$list($elm$json$Json$Decode$value));
	});
var $author$project$Types$Stats = F9(
	function (totalLeads, hotLeads, totalClients, openTasks, overdueTasks, stageCounts, sourceCounts, upcomingTasks, recentActivity) {
		return {cW: hotLeads, c5: openTasks, c6: overdueTasks, df: recentActivity, dn: sourceCounts, dp: stageCounts, dv: totalClients, dw: totalLeads, dx: upcomingTasks};
	});
var $author$project$Types$statsDecoder = function () {
	var stageCount = A3(
		$elm$json$Json$Decode$map2,
		F2(
			function (s, c) {
				return {aH: c, $7: s};
			}),
		A2($elm$json$Json$Decode$field, 'scStage', $elm$json$Json$Decode$string),
		A2($elm$json$Json$Decode$field, 'scCount', $elm$json$Json$Decode$int));
	var sourceCount = A3(
		$elm$json$Json$Decode$map2,
		F2(
			function (s, c) {
				return {aH: c, ah: s};
			}),
		A2($elm$json$Json$Decode$field, 'srcSource', $elm$json$Json$Decode$string),
		A2($elm$json$Json$Decode$field, 'srcCount', $elm$json$Json$Decode$int));
	return A3(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
		'stRecentActivity',
		$elm$json$Json$Decode$list($author$project$Types$activityDecoder),
		A3(
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
			'stUpcomingTasks',
			$elm$json$Json$Decode$list($author$project$Types$taskDecoder),
			A3(
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
				'stSourceCounts',
				$elm$json$Json$Decode$list(sourceCount),
				A3(
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
					'stStageCounts',
					$elm$json$Json$Decode$list(stageCount),
					A3(
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
						'stOverdueTasks',
						$elm$json$Json$Decode$int,
						A3(
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
							'stOpenTasks',
							$elm$json$Json$Decode$int,
							A3(
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
								'stTotalClients',
								$elm$json$Json$Decode$int,
								A3(
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
									'stHotLeads',
									$elm$json$Json$Decode$int,
									A3(
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required,
										'stTotalLeads',
										$elm$json$Json$Decode$int,
										$elm$json$Json$Decode$succeed($author$project$Types$Stats))))))))));
}();
var $author$project$Api$fetchStats = function (ctx) {
	return A5($author$project$Api$authedRequest, ctx, 'GET', '/api/stats', $elm$core$Maybe$Nothing, $author$project$Types$statsDecoder);
};
var $author$project$Api$fetchTasksPage = F2(
	function (ctx, offset) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'GET',
			'/api/tasks?limit=50&offset=' + $elm$core$String$fromInt(offset),
			$elm$core$Maybe$Nothing,
			$elm$json$Json$Decode$list($author$project$Types$taskDecoder));
	});
var $author$project$Api$fetchUsers = function (ctx) {
	return A5(
		$author$project$Api$authedRequest,
		ctx,
		'GET',
		'/api/users',
		$elm$core$Maybe$Nothing,
		$elm$json$Json$Decode$list($author$project$Types$userDecoder));
};
var $elm$core$String$replace = F3(
	function (before, after, string) {
		return A2(
			$elm$core$String$join,
			after,
			A2($elm$core$String$split, before, string));
	});
var $author$project$Main$inlinePath = F2(
	function (model, cid) {
		return 'record/' + ((A2($elm$core$String$startsWith, 'case:', model.Z) ? A3($elm$core$String$replace, ':', '/', model.Z) : ('client/' + $elm$core$String$fromInt(cid))) + ('/' + model.bb));
	});
var $author$project$Main$routeCmd = F2(
	function (model, route) {
		var ctx = {M: model.ak, du: model.du};
		var alwaysFetch = $elm$core$Platform$Cmd$batch(
			_List_fromArray(
				[
					A3(
					$author$project$Api$fetchTasksPage,
					ctx,
					model.c8,
					A2($author$project$Main$acceptLoad, model, $author$project$State$TasksLoaded))
				]));
		switch (route.$) {
			case 0:
				return $elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							A2(
							$author$project$Api$fetchStats,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$StatsLoaded)),
							A2(
							$author$project$Api$fetchLeads,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$LeadsLoaded))
						]));
			case 1:
				return $elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							A4(
							$author$project$Api$fetchFilteredLeads,
							ctx,
							model,
							model.c8,
							A2($author$project$Main$acceptLoad, model, $author$project$State$LeadsLoaded)),
							A2(
							$author$project$Api$fetchUsers,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$UsersLoaded))
						]));
			case 2:
				var id = route.a;
				return $elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							A3(
							$author$project$Api$fetchLeadDetail,
							ctx,
							id,
							A2($author$project$Main$acceptLoad, model, $author$project$State$DetailLoaded)),
							A2(
							$author$project$Api$fetchUsers,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$UsersLoaded))
						]));
			case 3:
				return $elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							A4(
							$author$project$Api$fetchClientsPage,
							ctx,
							model.c8,
							model.aG,
							A2($author$project$Main$acceptLoad, model, $author$project$State$ClientsLoaded)),
							A2(
							$author$project$Api$fetchUsers,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$UsersLoaded))
						]));
			case 4:
				var id = route.a;
				return $elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							A3(
							$author$project$Api$fetchClientDetail,
							ctx,
							id,
							A2($author$project$Main$acceptLoad, model, $author$project$State$ClientDetailLoaded)),
							A5(
							$author$project$Api$featureGet,
							ctx,
							A2($author$project$Main$inlinePath, model, id),
							model.a7,
							model.c8,
							A2($author$project$Main$acceptLoad, model, $author$project$State$FeatureLoaded)),
							A2(
							$author$project$Api$fetchUsers,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$UsersLoaded))
						]));
			case 5:
				return $elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							A3(
							$author$project$Api$fetchTasksPage,
							ctx,
							model.c8,
							A2($author$project$Main$acceptLoad, model, $author$project$State$TasksLoaded)),
							A2(
							$author$project$Api$fetchLeads,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$LeadsLoaded)),
							A2(
							$author$project$Api$fetchClients,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$ClientsLoaded))
						]));
			case 6:
				return A2(
					$author$project$Api$fetchUsers,
					ctx,
					A2($author$project$Main$acceptLoad, model, $author$project$State$UsersLoaded));
			case 7:
				return A3(
					$author$project$Api$fetchAudit,
					ctx,
					200,
					A2($author$project$Main$acceptLoad, model, $author$project$State$AuditLoaded));
			default:
				var kind = route.a;
				return A2($elm$core$String$startsWith, 'work/', kind) ? A5(
					$author$project$Api$featureGet,
					ctx,
					A2($elm$core$String$dropLeft, 5, kind),
					model.a7,
					model.c8,
					A2($author$project$Main$acceptLoad, model, $author$project$State$FeatureLoaded)) : A4(
					$author$project$Api$fetchOperations,
					ctx,
					kind,
					model.c8,
					A2($author$project$Main$acceptLoad, model, $author$project$State$OperationsLoaded));
		}
	});
var $author$project$Main$reloadCurrent = function (model) {
	return A2(
		$author$project$Main$routeCmd,
		model,
		$author$project$State$routeOf(model.a_));
};
var $elm$core$Set$remove = F2(
	function (key, _v0) {
		var dict = _v0;
		return A2($elm$core$Dict$remove, key, dict);
	});
var $elm$browser$Browser$Navigation$replaceUrl = _Browser_replaceUrl;
var $author$project$Api$resetPassword = F3(
	function (ctx, token, password) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/auth/reset',
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(
					$elm$json$Json$Encode$object(
						_List_fromArray(
							[
								_Utils_Tuple2(
								'token',
								$elm$json$Json$Encode$string(token)),
								_Utils_Tuple2(
								'password',
								$elm$json$Json$Encode$string(password))
							])))),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Main$resultError = function (result) {
	if (!result.$) {
		return '';
	} else {
		var err = result.a;
		return $author$project$Main$httpError(err);
	}
};
var $author$project$Features$str = F2(
	function (key, item) {
		return A2(
			$elm$core$Result$withDefault,
			'',
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, key, $author$project$Features$scalar),
				item));
	});
var $author$project$Features$rowForm = function (row) {
	var values = $author$project$Features$formValues(row);
	var rid = A2($author$project$Features$str, 'id', row);
	return A3(
		$elm$core$Dict$insert,
		'user',
		rid,
		A3(
			$elm$core$Dict$insert,
			'session',
			rid,
			A3(
				$elm$core$Dict$insert,
				'request',
				'request:' + rid,
				A3(
					$elm$core$Dict$insert,
					'expectedRevision',
					A2($author$project$Features$str, 'revision', row),
					values))));
};
var $elm$json$Json$Encode$bool = _Json_wrap;
var $author$project$Main$saveDark = _Platform_outgoingPort('saveDark', $elm$json$Json$Encode$bool);
var $elm$core$Maybe$destruct = F3(
	function (_default, func, maybe) {
		if (!maybe.$) {
			var a = maybe.a;
			return func(a);
		} else {
			return _default;
		}
	});
var $author$project$Main$saveToken = _Platform_outgoingPort(
	'saveToken',
	function ($) {
		return A3($elm$core$Maybe$destruct, $elm$json$Json$Encode$null, $elm$json$Json$Encode$string, $);
	});
var $author$project$Api$setTaskStatus = F4(
	function (ctx, id, revision, status) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'PATCH',
			'/api/tasks/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(
					$elm$json$Json$Encode$object(
						_List_fromArray(
							[
								_Utils_Tuple2(
								'tsrStatus',
								$elm$json$Json$Encode$string(status)),
								_Utils_Tuple2(
								'expectedRevision',
								$elm$json$Json$Encode$int(revision))
							])))),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Main$startsLoad = function (msg) {
	_v0$48:
	while (true) {
		switch (msg.$) {
			case 40:
				return true;
			case 10:
				return true;
			case 11:
				return true;
			case 26:
				return true;
			case 27:
				return true;
			case 16:
				return true;
			case 17:
				return true;
			case 25:
				return true;
			case 31:
				return true;
			case 35:
				return true;
			case 37:
				return true;
			case 36:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 29:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 76:
				return true;
			case 99:
				return true;
			case 77:
				return true;
			case 78:
				return true;
			case 79:
				return true;
			case 80:
				return true;
			case 81:
				return true;
			case 82:
				return true;
			case 49:
				return true;
			case 9:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 140:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 142:
				return true;
			case 14:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 62:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 66:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 68:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 70:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 72:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 75:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 88:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 90:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 92:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 98:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 105:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 104:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 107:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 112:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 114:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 119:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 120:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 122:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 125:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 131:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 132:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			case 134:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$48;
				}
			default:
				break _v0$48;
		}
	}
	return false;
};
var $author$project$Main$startsUserLoad = function (msg) {
	_v0$7:
	while (true) {
		switch (msg.$) {
			case 131:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$7;
				}
			case 132:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$7;
				}
			case 134:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$7;
				}
			case 49:
				return true;
			case 9:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$7;
				}
			case 140:
				if (!msg.a.$) {
					return true;
				} else {
					break _v0$7;
				}
			case 40:
				return true;
			default:
				break _v0$7;
		}
	}
	return false;
};
var $author$project$Types$encodeNewTask = function (f) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'ntLeadId',
				$elm$json$Json$Encode$int(f.aP)),
				_Utils_Tuple2(
				'ntTitle',
				$elm$json$Json$Encode$string(f.ay)),
				_Utils_Tuple2(
				'ntDescription',
				$author$project$Types$encodeNonEmpty(f.a4)),
				_Utils_Tuple2(
				'ntDueDate',
				$author$project$Types$maybeDate(f.aK)),
				_Utils_Tuple2(
				'ntPriority',
				$author$project$Types$encodeNonEmpty(f.bl))
			]));
};
var $author$project$Main$submitTask = F3(
	function (model, ctx, leadId) {
		return ($elm$core$String$trim(model.k.ay) === '') ? _Utils_Tuple2(model, $elm$core$Platform$Cmd$none) : _Utils_Tuple2(
			model,
			A3(
				$author$project$Api$createTask,
				ctx,
				$author$project$Types$encodeNewTask(
					{a4: model.k.a4, aK: model.k.aK, aP: leadId, bl: model.k.bl, ay: model.k.ay}),
				$author$project$State$AddTaskDone));
	});
var $elm$core$List$takeReverse = F3(
	function (n, list, kept) {
		takeReverse:
		while (true) {
			if (n <= 0) {
				return kept;
			} else {
				if (!list.b) {
					return kept;
				} else {
					var x = list.a;
					var xs = list.b;
					var $temp$n = n - 1,
						$temp$list = xs,
						$temp$kept = A2($elm$core$List$cons, x, kept);
					n = $temp$n;
					list = $temp$list;
					kept = $temp$kept;
					continue takeReverse;
				}
			}
		}
	});
var $elm$core$List$takeTailRec = F2(
	function (n, list) {
		return $elm$core$List$reverse(
			A3($elm$core$List$takeReverse, n, list, _List_Nil));
	});
var $elm$core$List$takeFast = F3(
	function (ctr, n, list) {
		if (n <= 0) {
			return _List_Nil;
		} else {
			var _v0 = _Utils_Tuple2(n, list);
			_v0$1:
			while (true) {
				_v0$5:
				while (true) {
					if (!_v0.b.b) {
						return list;
					} else {
						if (_v0.b.b.b) {
							switch (_v0.a) {
								case 1:
									break _v0$1;
								case 2:
									var _v2 = _v0.b;
									var x = _v2.a;
									var _v3 = _v2.b;
									var y = _v3.a;
									return _List_fromArray(
										[x, y]);
								case 3:
									if (_v0.b.b.b.b) {
										var _v4 = _v0.b;
										var x = _v4.a;
										var _v5 = _v4.b;
										var y = _v5.a;
										var _v6 = _v5.b;
										var z = _v6.a;
										return _List_fromArray(
											[x, y, z]);
									} else {
										break _v0$5;
									}
								default:
									if (_v0.b.b.b.b && _v0.b.b.b.b.b) {
										var _v7 = _v0.b;
										var x = _v7.a;
										var _v8 = _v7.b;
										var y = _v8.a;
										var _v9 = _v8.b;
										var z = _v9.a;
										var _v10 = _v9.b;
										var w = _v10.a;
										var tl = _v10.b;
										return (ctr > 1000) ? A2(
											$elm$core$List$cons,
											x,
											A2(
												$elm$core$List$cons,
												y,
												A2(
													$elm$core$List$cons,
													z,
													A2(
														$elm$core$List$cons,
														w,
														A2($elm$core$List$takeTailRec, n - 4, tl))))) : A2(
											$elm$core$List$cons,
											x,
											A2(
												$elm$core$List$cons,
												y,
												A2(
													$elm$core$List$cons,
													z,
													A2(
														$elm$core$List$cons,
														w,
														A3($elm$core$List$takeFast, ctr + 1, n - 4, tl)))));
									} else {
										break _v0$5;
									}
							}
						} else {
							if (_v0.a === 1) {
								break _v0$1;
							} else {
								break _v0$5;
							}
						}
					}
				}
				return list;
			}
			var _v1 = _v0.b;
			var x = _v1.a;
			return _List_fromArray(
				[x]);
		}
	});
var $elm$core$List$take = F2(
	function (n, list) {
		return A3($elm$core$List$takeFast, 0, n, list);
	});
var $elm$url$Url$addPort = F2(
	function (maybePort, starter) {
		if (maybePort.$ === 1) {
			return starter;
		} else {
			var port_ = maybePort.a;
			return starter + (':' + $elm$core$String$fromInt(port_));
		}
	});
var $elm$url$Url$addPrefixed = F3(
	function (prefix, maybeSegment, starter) {
		if (maybeSegment.$ === 1) {
			return starter;
		} else {
			var segment = maybeSegment.a;
			return _Utils_ap(
				starter,
				_Utils_ap(prefix, segment));
		}
	});
var $elm$url$Url$toString = function (url) {
	var http = function () {
		var _v0 = url.b3;
		if (!_v0) {
			return 'http://';
		} else {
			return 'https://';
		}
	}();
	return A3(
		$elm$url$Url$addPrefixed,
		'#',
		url.bJ,
		A3(
			$elm$url$Url$addPrefixed,
			'?',
			url.dd,
			_Utils_ap(
				A2(
					$elm$url$Url$addPort,
					url.b$,
					_Utils_ap(http, url.bN)),
				url.A)));
};
var $author$project$State$ToastPushed = F2(
	function (a, b) {
		return {$: 145, a: a, b: b};
	});
var $author$project$Main$toast = F2(
	function (kind, textMsg) {
		return A2(
			$elm$core$Task$perform,
			$elm$core$Basics$identity,
			$elm$core$Task$succeed(
				A2($author$project$State$ToastPushed, kind, textMsg)));
	});
var $elm$core$Dict$foldl = F3(
	function (func, acc, dict) {
		foldl:
		while (true) {
			if (dict.$ === -2) {
				return acc;
			} else {
				var key = dict.b;
				var value = dict.c;
				var left = dict.d;
				var right = dict.e;
				var $temp$func = func,
					$temp$acc = A3(
					func,
					key,
					value,
					A3($elm$core$Dict$foldl, func, acc, left)),
					$temp$dict = right;
				func = $temp$func;
				acc = $temp$acc;
				dict = $temp$dict;
				continue foldl;
			}
		}
	});
var $elm$core$Dict$union = F2(
	function (t1, t2) {
		return A3($elm$core$Dict$foldl, $elm$core$Dict$insert, t2, t1);
	});
var $author$project$Api$updateClient = F3(
	function (ctx, id, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'PATCH',
			'/api/clients/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$updateLead = F3(
	function (ctx, id, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'PATCH',
			'/api/leads/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Types$leadDecoder);
	});
var $author$project$Api$updateUser = F3(
	function (ctx, id, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'PATCH',
			'/api/users/' + $elm$core$String$fromInt(id),
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Api$ignoreDecoder);
	});
var $author$project$Api$uploadDocument = F5(
	function (ctx, path, file, decoder, toMsg) {
		return $elm$http$Http$request(
			{
				aE: $elm$http$Http$multipartBody(
					_List_fromArray(
						[
							A2($elm$http$Http$filePart, 'file', file)
						])),
				aL: A2($author$project$Api$expectJson, toMsg, decoder),
				a8: _List_Nil,
				be: 'POST',
				br: $elm$core$Maybe$Just(30000),
				bs: $elm$core$Maybe$Nothing,
				a_: _Utils_ap(ctx.M, path)
			});
	});
var $author$project$Api$uploadClientDocument = F3(
	function (ctx, id, file) {
		return A4(
			$author$project$Api$uploadDocument,
			ctx,
			'/api/clients/' + ($elm$core$String$fromInt(id) + '/documents'),
			file,
			$author$project$Types$clientDetailDecoder);
	});
var $author$project$Api$uploadLeadDocument = F3(
	function (ctx, id, file) {
		return A4(
			$author$project$Api$uploadDocument,
			ctx,
			'/api/leads/' + ($elm$core$String$fromInt(id) + '/documents'),
			file,
			$author$project$Types$leadDetailDecoder);
	});
var $author$project$Api$upsertCase = F3(
	function (ctx, clientId, body) {
		return A5(
			$author$project$Api$authedRequest,
			ctx,
			'POST',
			'/api/clients/' + ($elm$core$String$fromInt(clientId) + '/cases'),
			$elm$core$Maybe$Just(
				$elm$http$Http$jsonBody(body)),
			$author$project$Types$clientDetailDecoder);
	});
var $author$project$State$userFormOf = function (u) {
	return {
		ap: u.ap,
		t: u.t,
		ab: '',
		m: u.m,
		aX: u.aX,
		ch: $elm$core$Maybe$Just(u.a9)
	};
};
var $author$project$Main$update = F2(
	function (msg, model) {
		update:
		while (true) {
			if (!msg.$) {
				var key = msg.a;
				var loaded = msg.b;
				if (_Utils_eq(
					key,
					A2($author$project$Main$loadKeyFor, loaded, model))) {
					var $temp$msg = loaded,
						$temp$model = model;
					msg = $temp$msg;
					model = $temp$model;
					continue update;
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			} else {
				return $author$project$Main$expiredSession(msg) ? _Utils_Tuple2(
					_Utils_update(
						model,
						{aD: _List_Nil, L: true, cB: $elm$core$Maybe$Nothing, cC: $elm$core$Maybe$Nothing, am: _List_Nil, bz: $elm$json$Json$Encode$null, cD: $elm$core$Dict$empty, bA: $elm$core$Dict$empty, x: $elm$core$Maybe$Nothing, Y: $elm$core$Dict$empty, aq: false, aM: $elm$json$Json$Encode$null, cT: $elm$core$Dict$empty, a6: $elm$json$Json$Encode$null, P: _List_Nil, as: model.as + 1, s: 'Your session has expired. Please sign in again.', at: '', G: '', bY: _List_Nil, c9: $elm$json$Json$Encode$null, db: $elm$core$Maybe$Nothing, u: $elm$json$Json$Encode$null, J: _List_Nil, du: $elm$core$Maybe$Nothing, a$: $elm$core$Maybe$Nothing, aB: model.aB + 1, T: _List_Nil}),
					$author$project$Main$saveToken($elm$core$Maybe$Nothing)) : A2(
					$author$project$Main$updateHelp,
					msg,
					_Utils_update(
						model,
						{
							as: model.as + ($author$project$Main$startsLoad(msg) ? 1 : 0),
							aB: model.aB + ($author$project$Main$startsUserLoad(msg) ? 1 : 0)
						}));
			}
		}
	});
var $author$project$Main$updateHelp = F2(
	function (msg, model) {
		var ctx = {M: model.ak, du: model.du};
		switch (msg.$) {
			case 1:
				var message = msg.a;
				var action = msg.b;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							an: $elm$core$Maybe$Just(
								_Utils_Tuple2(message, action))
						}),
					$elm$core$Platform$Cmd$none);
			case 3:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{an: $elm$core$Maybe$Nothing}),
					$elm$core$Platform$Cmd$none);
			case 2:
				var _v1 = model.an;
				if (!_v1.$) {
					var _v2 = _v1.a;
					var action = _v2.b;
					return A2(
						$author$project$Main$update,
						action,
						_Utils_update(
							model,
							{an: $elm$core$Maybe$Nothing}));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 0:
				return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
			case 30:
				var value = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{at: value}),
					$elm$core$Platform$Cmd$none);
			case 15:
				var result = msg.a;
				if (!result.$) {
					var value = result.a;
					var pref = A2(
						$elm$core$Dict$map,
						F2(
							function (key, v) {
								return A2(
									$elm$core$List$member,
									key,
									_List_fromArray(
										['assignments', 'deadlines', 'documents', 'escalations', 'emailEnabled'])) ? (((v === '1') || (v === 'true')) ? 'true' : 'false') : v;
							}),
						$author$project$Features$rowForm(
							A2(
								$elm$core$Result$withDefault,
								$elm$json$Json$Encode$null,
								A2(
									$elm$json$Json$Decode$decodeValue,
									A2($elm$json$Json$Decode$field, 'security', $elm$json$Json$Decode$value),
									value))));
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								aM: value,
								cT: ($author$project$Main$featureSection(model) === 'notifications') ? A2($elm$core$Dict$union, pref, model.cT) : (((model.Z !== '') && _Utils_eq(
									A2($elm$core$Dict$get, 'owner', model.cT),
									$elm$core$Maybe$Nothing)) ? A3($elm$core$Dict$insert, 'owner', model.Z, model.cT) : model.cT),
								bY: A2(
									$elm$core$Result$withDefault,
									_List_Nil,
									A2(
										$elm$json$Json$Decode$decodeValue,
										A2(
											$elm$json$Json$Decode$field,
											'rows',
											$elm$json$Json$Decode$list($elm$json$Json$Decode$value)),
										value)),
								j: '',
								c7: false
							}),
						$elm$core$Platform$Cmd$none);
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								j: $author$project$Main$httpError(err),
								c7: false
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 16:
				var section = msg.a;
				var next = _Utils_update(
					model,
					{
						cB: $elm$core$Maybe$Nothing,
						aq: false,
						bH: '',
						cT: A3(
							$elm$core$Dict$insert,
							'owner',
							model.Z,
							$author$project$Features$defaults(section)),
						a6: $elm$json$Json$Encode$null,
						a7: '',
						bb: section,
						c8: 0
					});
				return _Utils_Tuple2(
					next,
					$author$project$Main$reloadCurrent(next));
			case 17:
				var own = msg.a;
				var next = _Utils_update(
					model,
					{
						aq: false,
						bH: '',
						cT: A3(
							$elm$core$Dict$insert,
							'owner',
							own,
							$author$project$Features$defaults(model.bb)),
						a6: $elm$json$Json$Encode$null,
						a7: '',
						Z: own,
						c8: 0
					});
				return _Utils_Tuple2(
					next,
					$author$project$Main$reloadCurrent(next));
			case 18:
				var file = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cB: $elm$core$Maybe$Just(file)
						}),
					$elm$core$Platform$Cmd$none);
			case 19:
				var rid = msg.a;
				var revision = msg.b;
				var _v4 = model.cB;
				if (!_v4.$) {
					var file = _v4.a;
					return model.aq ? _Utils_Tuple2(model, $elm$core$Platform$Cmd$none) : _Utils_Tuple2(
						_Utils_update(
							model,
							{
								aq: true,
								bH: '',
								cT: A3(
									$elm$core$Dict$insert,
									'id',
									$elm$core$String$fromInt(rid),
									model.cT)
							}),
						A5(
							$author$project$Api$checklistUpload,
							ctx,
							rid,
							revision,
							file,
							A2($author$project$Main$acceptLoad, model, $author$project$State$FeatureDone)));
				} else {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{bH: 'Choose a file to upload.'}),
						$elm$core$Platform$Cmd$none);
				}
			case 20:
				var result = msg.a;
				if (!result.$) {
					var current = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{bz: current}),
						$elm$core$Platform$Cmd$none);
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								bH: $author$project$Main$httpError(err)
							}),
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(err)));
				}
			case 22:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{bz: $elm$json$Json$Encode$null}),
					$elm$core$Platform$Cmd$none);
			case 23:
				var key = msg.a;
				var latest = A2(
					$elm$core$Maybe$withDefault,
					'',
					A2(
						$elm$core$Dict$get,
						key,
						$author$project$Features$formValues(model.bz)));
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cD: A3($elm$core$Dict$insert, key, latest, model.cD),
							cT: A3($elm$core$Dict$insert, key, latest, model.cT)
						}),
					$elm$core$Platform$Cmd$none);
			case 21:
				var uf = model.B;
				var revision = A2(
					$elm$core$Result$withDefault,
					0,
					A2(
						$elm$json$Json$Decode$decodeValue,
						A2($elm$json$Json$Decode$field, 'revision', $elm$json$Json$Decode$int),
						model.bz));
				var ef = model.N;
				var cf = model.n;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							w: A2(
								$elm$core$Maybe$map,
								function (f) {
									return _Utils_update(
										f,
										{
											m: (model.cE === 'cases') ? revision : f.m
										});
								},
								model.w),
							n: _Utils_update(
								cf,
								{
									m: (model.cE === 'clients') ? revision : cf.m
								}),
							bz: $elm$json$Json$Encode$null,
							N: _Utils_update(
								ef,
								{
									m: (model.cE === 'leads') ? revision : ef.m
								}),
							Y: $author$project$Features$formValues(model.bz),
							bH: 'Comparison accepted. Review your form and save when ready.',
							cT: A3(
								$elm$core$Dict$insert,
								'expectedRevision',
								$elm$core$String$fromInt(revision),
								model.cT),
							u: model.bz,
							B: _Utils_update(
								uf,
								{
									m: (model.cE === 'users') ? revision : uf.m
								})
						}),
					$elm$core$Platform$Cmd$none);
			case 24:
				var key = msg.a;
				var value = msg.b;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cT: A3($elm$core$Dict$insert, key, value, model.cT)
						}),
					$elm$core$Platform$Cmd$none);
			case 25:
				var query = msg.a;
				var next = _Utils_update(
					model,
					{a7: query, c7: true, c8: 0});
				return _Utils_Tuple2(
					next,
					$author$project$Main$reloadCurrent(next));
			case 26:
				var row = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							bz: $elm$json$Json$Encode$null,
							Y: $author$project$Features$formValues(row),
							aq: false,
							bH: '',
							cT: A2(
								$elm$core$Dict$union,
								$author$project$Features$rowForm(row),
								A3(
									$elm$core$Dict$insert,
									'owner',
									model.Z,
									$author$project$Features$defaults(
										$author$project$Main$featureSection(model)))),
							a6: $elm$json$Json$Encode$null
						}),
					$elm$core$Platform$Cmd$none);
			case 27:
				var next = _Utils_update(
					model,
					{
						bz: $elm$json$Json$Encode$null,
						aq: false,
						bH: '',
						cT: A3(
							$elm$core$Dict$insert,
							'owner',
							model.Z,
							$author$project$Features$defaults(
								$author$project$Main$featureSection(model))),
						a6: $elm$json$Json$Encode$null
					});
				return _Utils_Tuple2(
					next,
					$author$project$Main$reloadCurrent(next));
			case 28:
				var action = msg.a;
				if (model.aq) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					if ((action === 'apply') && ($author$project$Main$featureSection(model) === 'search')) {
						var next = _Utils_update(
							model,
							{
								a6: $elm$json$Json$Encode$null,
								a7: '@view:' + A2(
									$elm$core$Maybe$withDefault,
									'',
									A2($elm$core$Dict$get, 'id', model.cT)),
								c7: true,
								c8: 0
							});
						return _Utils_Tuple2(
							next,
							$author$project$Main$reloadCurrent(next));
					} else {
						if (action === 'range') {
							var next = _Utils_update(
								model,
								{
									a7: A2(
										$elm$core$Maybe$withDefault,
										'',
										A2($elm$core$Dict$get, 'from', model.cT)) + (',' + A2(
										$elm$core$Maybe$withDefault,
										'',
										A2($elm$core$Dict$get, 'to', model.cT))),
									c7: true
								});
							return _Utils_Tuple2(
								next,
								$author$project$Main$reloadCurrent(next));
						} else {
							return _Utils_Tuple2(
								_Utils_update(
									model,
									{aq: true, bH: ''}),
								A4(
									$author$project$Api$featurePost,
									ctx,
									$author$project$Main$featureSection(model) + ('/' + action),
									$elm$json$Json$Encode$object(
										A2(
											$elm$core$List$map,
											$elm$core$Tuple$mapSecond($elm$json$Json$Encode$string),
											$elm$core$Dict$toList(
												((model.Z !== '') && (A2(
													$elm$core$Maybe$withDefault,
													'',
													A2($elm$core$Dict$get, 'owner', model.cT)) === '')) ? A3($elm$core$Dict$insert, 'owner', model.Z, model.cT) : model.cT))),
									A2($author$project$Main$acceptLoad, model, $author$project$State$FeatureDone)));
						}
					}
				}
			case 29:
				var result = msg.a;
				if (!result.$) {
					var value = result.a;
					var addRevision = F2(
						function (key, fields) {
							var _v7 = A2(
								$elm$json$Json$Decode$decodeValue,
								A2($elm$json$Json$Decode$field, key, $elm$json$Json$Decode$int),
								value);
							if (!_v7.$) {
								var n = _v7.a;
								return A3(
									$elm$core$Dict$insert,
									key,
									$elm$core$String$fromInt(n),
									fields);
							} else {
								return fields;
							}
						});
					var form = A3(
						$elm$core$List$foldl,
						addRevision,
						model.cT,
						_List_fromArray(
							['sourceRevision', 'targetRevision']));
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								cB: $elm$core$Maybe$Nothing,
								aq: false,
								bH: '',
								cT: A2(
									$elm$core$Dict$remove,
									'password',
									A2($elm$core$Dict$remove, 'code', form)),
								a6: value
							}),
						$author$project$Main$reloadCurrent(model));
				} else {
					if ((result.a.$ === 3) && (result.a.a === 409)) {
						if (!A2(
							$elm$core$List$member,
							$author$project$Main$featureSection(model),
							_List_fromArray(
								['tasks', 'documents', 'reminders', 'appointments', 'invoices', 'notifications']))) {
							return _Utils_Tuple2(
								_Utils_update(
									model,
									{aq: false, bH: 'This action is unavailable in its current state. Refresh or preview the latest records. Email retries require an exhausted failure, no active send, and fewer than three manual retries spaced 15 minutes apart.'}),
								$elm$core$Platform$Cmd$none);
						} else {
							var rid = A2(
								$elm$core$Maybe$withDefault,
								0,
								A2(
									$elm$core$Maybe$andThen,
									$elm$core$String$toInt,
									A2(
										$elm$core$Dict$get,
										($author$project$Main$featureSection(model) === 'reminders') ? 'task' : 'id',
										model.cT)));
							return A5(
								$author$project$Main$beginConflict,
								_Utils_update(
									model,
									{aq: false, bH: 'The item changed. Compare the current version below.'}),
								$author$project$Main$featureSection(model),
								rid,
								$author$project$Main$dictValue(model.Y),
								$author$project$Main$dictValue(model.cT));
						}
					} else {
						var err = result.a;
						return _Utils_Tuple2(
							_Utils_update(
								model,
								{
									aq: false,
									bH: $author$project$Main$httpError(err)
								}),
							A2(
								$author$project$Main$toast,
								'error',
								$author$project$Main$httpError(err)));
					}
				}
			case 31:
				var token = msg.a;
				return _Utils_Tuple2(
					model,
					A4(
						$author$project$Api$portalPost,
						ctx,
						'exchange',
						$elm$json$Json$Encode$object(
							_List_fromArray(
								[
									_Utils_Tuple2(
									'token',
									$elm$json$Json$Encode$string(token))
								])),
						$author$project$State$PortalExchanged));
			case 32:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{da: ''}),
						A2($elm$browser$Browser$Navigation$replaceUrl, model.q, '/portal'));
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								da: $author$project$Main$httpError(err)
							}),
						A2($elm$browser$Browser$Navigation$replaceUrl, model.q, '/portal'));
				}
			case 33:
				var result = msg.a;
				if (!result.$) {
					var value = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{c9: value, da: ''}),
						$elm$core$Platform$Cmd$none);
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								c9: $elm$json$Json$Encode$null,
								da: $author$project$Main$httpError(err)
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 34:
				var file = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							db: $elm$core$Maybe$Just(file)
						}),
					$elm$core$Platform$Cmd$none);
			case 35:
				var rid = msg.a;
				var _v10 = model.db;
				if (!_v10.$) {
					var file = _v10.a;
					return _Utils_Tuple2(
						model,
						A4(
							$author$project$Api$portalUpload,
							ctx,
							rid,
							file,
							A2($author$project$Main$acceptLoad, model, $author$project$State$PortalUploaded)));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 36:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{db: $elm$core$Maybe$Nothing}),
						A2(
							$author$project$Api$portalGet,
							ctx,
							A2($author$project$Main$acceptLoad, model, $author$project$State$PortalLoaded)));
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								da: $author$project$Main$httpError(err)
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 37:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{c9: $elm$json$Json$Encode$null, da: 'Signed out', db: $elm$core$Maybe$Nothing}),
					A4(
						$author$project$Api$portalPost,
						ctx,
						'logout',
						$elm$json$Json$Encode$object(_List_Nil),
						function (_v12) {
							return $author$project$State$NoOp;
						}));
			case 4:
				var mode = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{s: '', bT: mode, aQ: '', G: ''}),
					$elm$core$Platform$Cmd$none);
			case 5:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{C: true, s: ''}),
					A3($author$project$Api$recover, ctx, model.bc, $author$project$State$RecoveryDone));
			case 6:
				var resetToken = A2(
					$elm$core$Maybe$withDefault,
					'',
					$elm$url$Url$percentDecode(
						A2(
							$elm$core$String$dropLeft,
							6,
							A2($elm$core$Maybe$withDefault, '', model.a_.dd))));
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{C: true, s: ''}),
					A4($author$project$Api$resetPassword, ctx, resetToken, model.G, $author$project$State$ResetDone));
			case 7:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{C: false, aQ: 'If your account exists, you’ll receive an email with a link that expires in one hour.'}),
						$elm$core$Platform$Cmd$none);
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								C: false,
								s: $author$project$Main$httpError(err)
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 8:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{C: false, bT: 'login', aQ: 'Password updated. Sign in with your new password.', G: ''}),
						A2($elm$browser$Browser$Navigation$replaceUrl, model.q, '/'));
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								C: false,
								s: $author$project$Main$httpError(err)
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 9:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{aD: _List_Nil, L: true, cB: $elm$core$Maybe$Nothing, cC: $elm$core$Maybe$Nothing, am: _List_Nil, bz: $elm$json$Json$Encode$null, cD: $elm$core$Dict$empty, bA: $elm$core$Dict$empty, x: $elm$core$Maybe$Nothing, Y: $elm$core$Dict$empty, aq: false, aM: $elm$json$Json$Encode$null, cT: $elm$core$Dict$empty, a6: $elm$json$Json$Encode$null, P: _List_Nil, at: '', G: '', bY: _List_Nil, c9: $elm$json$Json$Encode$null, db: $elm$core$Maybe$Nothing, u: $elm$json$Json$Encode$null, J: _List_Nil, du: $elm$core$Maybe$Nothing, a$: $elm$core$Maybe$Nothing, T: _List_Nil}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									$author$project$Main$saveToken($elm$core$Maybe$Nothing),
									A2($elm$browser$Browser$Navigation$pushUrl, model.q, '/')
								])));
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(err)));
				}
			case 10:
				var step = msg.a;
				var next = _Utils_update(
					model,
					{
						c7: true,
						c8: A2($elm$core$Basics$max, 0, model.c8 + (step * 50)),
						v: $elm$core$Set$empty
					});
				return _Utils_Tuple2(
					next,
					A2(
						$author$project$Main$routeCmd,
						next,
						$author$project$State$routeOf(model.a_)));
			case 11:
				var kind = msg.a;
				var query = msg.b;
				return (((kind === 'leads') && _Utils_eq(query, model.dc)) || ((kind === 'clients') && _Utils_eq(query, model.aG))) ? _Utils_Tuple2(
					_Utils_update(
						model,
						{c7: true}),
					(kind === 'leads') ? A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						model,
						0,
						A2($author$project$Main$acceptLoad, model, $author$project$State$LeadsLoaded)) : A4(
						$author$project$Api$fetchClientsPage,
						ctx,
						0,
						query,
						A2($author$project$Main$acceptLoad, model, $author$project$State$ClientsLoaded))) : _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
			case 12:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							bY: A2($elm$core$Result$withDefault, _List_Nil, result),
							j: $author$project$Main$resultError(result),
							c7: false
						}),
					$elm$core$Platform$Cmd$none);
			case 13:
				var path = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$operation, ctx, path, $author$project$State$OperationDone));
			case 14:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Saved successfully'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var err = result.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(err)));
				}
			case 38:
				return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
			case 39:
				var request = msg.a;
				if (!request.$) {
					var url = request.a;
					return _Utils_Tuple2(
						model,
						A2(
							$elm$browser$Browser$Navigation$pushUrl,
							model.q,
							$elm$url$Url$toString(url)));
				} else {
					var href = request.a;
					return _Utils_Tuple2(
						model,
						$elm$browser$Browser$Navigation$load(href));
				}
			case 40:
				var url = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cB: $elm$core$Maybe$Nothing,
							cC: $elm$core$Maybe$Nothing,
							bz: $elm$json$Json$Encode$null,
							x: $elm$core$Maybe$Nothing,
							Y: $elm$core$Dict$empty,
							aq: false,
							bH: '',
							cT: $author$project$Features$defaults(
								A2($elm$core$String$dropLeft, 6, url.A)),
							a6: $elm$json$Json$Encode$null,
							a7: '',
							Z: $author$project$Main$ownerForUrl(url),
							aT: false,
							bY: _List_Nil,
							j: '',
							c7: true,
							c8: 0,
							R: $elm$core$Maybe$Nothing,
							aU: $elm$core$Maybe$Nothing,
							v: $elm$core$Set$empty,
							a_: url
						}),
					function () {
						if (url.A === '/portal') {
							var _v18 = url.bJ;
							if (!_v18.$) {
								var fragment = _v18.a;
								return A2(
									$elm$core$Task$perform,
									$elm$core$Basics$always(
										$author$project$State$PortalExchange(
											A2($elm$core$String$dropLeft, 6, fragment))),
									$elm$core$Task$succeed(0));
							} else {
								return A2(
									$author$project$Api$portalGet,
									ctx,
									A2(
										$author$project$Main$acceptLoad,
										_Utils_update(
											model,
											{a7: '', c8: 0, a_: url}),
										$author$project$State$PortalLoaded));
							}
						} else {
							if (_Utils_eq(model.a$, $elm$core$Maybe$Nothing)) {
								return $elm$core$Platform$Cmd$none;
							} else {
								return A2(
									$author$project$Main$routeCmd,
									_Utils_update(
										model,
										{a7: '', c8: 0, a_: url}),
									$author$project$State$routeOf(url));
							}
						}
					}());
			case 41:
				var t = msg.a;
				return _Utils_eq(t, $elm$core$Maybe$Nothing) ? _Utils_Tuple2(
					_Utils_update(
						model,
						{L: true}),
					$elm$core$Platform$Cmd$none) : _Utils_Tuple2(
					_Utils_update(
						model,
						{du: t}),
					A2(
						$author$project$Api$me,
						{M: model.ak, du: t},
						$author$project$State$MeDone));
			case 42:
				var flag = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{ao: flag}),
					$elm$core$Platform$Cmd$none);
			case 43:
				var newFlag = !model.ao;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{ao: newFlag}),
					$author$project$Main$saveDark(newFlag));
			case 143:
				var iso = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{cf: iso}),
					$elm$core$Platform$Cmd$none);
			case 44:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{bc: v, s: ''}),
					$elm$core$Platform$Cmd$none);
			case 45:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{s: '', G: v}),
					$elm$core$Platform$Cmd$none);
			case 46:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{C: true, s: ''}),
					A5($author$project$Api$login, ctx, model.bc, model.G, model.at, $author$project$State$LoginDone));
			case 47:
				if (!msg.a.$) {
					var resp = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								L: true,
								C: false,
								s: '',
								at: '',
								G: '',
								du: $elm$core$Maybe$Just(resp.du),
								a$: $elm$core$Maybe$Just(resp.a$)
							}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									$author$project$Main$saveToken(
									$elm$core$Maybe$Just(resp.du)),
									A2($author$project$Main$toast, 'success', 'Welcome back, ' + resp.a$.t),
									resp.a$.bf ? A2($elm$browser$Browser$Navigation$pushUrl, model.q, '/work/security') : A2(
									$author$project$Main$routeCmd,
									_Utils_update(
										model,
										{
											du: $elm$core$Maybe$Just(resp.du)
										}),
									$author$project$State$routeOf(model.a_))
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								C: false,
								s: _Utils_eq(
									e,
									$elm$http$Http$BadStatus(401)) ? 'Check your email, password, and authenticator or recovery code.' : $author$project$Main$httpError(e)
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 48:
				if (!msg.a.$) {
					var u = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								L: true,
								a$: $elm$core$Maybe$Just(u)
							}),
						u.bf ? A2($elm$browser$Browser$Navigation$pushUrl, model.q, '/work/security') : A2(
							$author$project$Main$routeCmd,
							model,
							$author$project$State$routeOf(model.a_)));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{L: true, du: $elm$core$Maybe$Nothing, a$: $elm$core$Maybe$Nothing}),
						$author$project$Main$saveToken($elm$core$Maybe$Nothing));
				}
			case 49:
				return _Utils_Tuple2(
					model,
					A2($author$project$Api$logout, ctx, $author$project$State$LogoutDone));
			case 50:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							P: A2($elm$core$Result$withDefault, model.P, result),
							j: $author$project$Main$resultError(result),
							c7: false
						}),
					$elm$core$Platform$Cmd$none);
			case 51:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							j: $author$project$Main$resultError(result),
							c7: false,
							T: A2($elm$core$Result$withDefault, model.T, result)
						}),
					$elm$core$Platform$Cmd$none);
			case 52:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							j: $author$project$Main$resultError(result),
							c7: false,
							J: A2($elm$core$Result$withDefault, model.J, result)
						}),
					$elm$core$Platform$Cmd$none);
			case 53:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							am: A2($elm$core$Result$withDefault, model.am, result),
							j: $author$project$Main$resultError(result),
							c7: false
						}),
					$elm$core$Platform$Cmd$none);
			case 54:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cC: $author$project$Main$justOf(result),
							j: $author$project$Main$resultError(result),
							c7: false
						}),
					$elm$core$Platform$Cmd$none);
			case 55:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							x: $author$project$Main$justOf(result),
							j: $author$project$Main$resultError(result),
							c7: false
						}),
					$elm$core$Platform$Cmd$none);
			case 56:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							j: $author$project$Main$resultError(result),
							c7: false,
							dq: $author$project$Main$justOf(result)
						}),
					$elm$core$Platform$Cmd$none);
			case 57:
				var result = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aD: A2($elm$core$Result$withDefault, model.aD, result)
						}),
					$elm$core$Platform$Cmd$none);
			case 58:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aC: $author$project$State$emptyAddLead, bn: true}),
					$elm$core$Platform$Cmd$none);
			case 59:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{bn: false}),
					$elm$core$Platform$Cmd$none);
			case 60:
				var f = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aC: f(model.aC)
						}),
					$elm$core$Platform$Cmd$none);
			case 61:
				return _Utils_Tuple2(
					model,
					A3(
						$author$project$Api$createLead,
						ctx,
						$author$project$Types$encodeNewLead(model.aC),
						$author$project$State$AddLeadDone));
			case 62:
				if (!msg.a.$) {
					var lead = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								P: A2($elm$core$List$cons, lead, model.P),
								bn: false
							}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Lead ' + (lead.bV + ' created')),
									A2($author$project$Main$navigateTo, model.q, '/leads')
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 63:
				var _v19 = model.x;
				if (_v19.$ === 1) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					var d = _v19.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								N: $author$project$State$editLeadOf(d.aO),
								a5: !model.a5,
								u: $author$project$Types$encodeUpdateLead(
									$author$project$State$editLeadOf(d.aO))
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 64:
				var f = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							N: f(model.N)
						}),
					$elm$core$Platform$Cmd$none);
			case 65:
				var _v20 = model.x;
				if (_v20.$ === 1) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					var d = _v20.a;
					return _Utils_Tuple2(
						model,
						A4(
							$author$project$Api$updateLead,
							ctx,
							d.aO.a9,
							$author$project$Types$encodeUpdateLead(model.N),
							$author$project$State$EditLeadDone));
				}
			case 66:
				if (!msg.a.$) {
					var lead = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{a5: false}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Lead updated'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					if ((msg.a.a.$ === 3) && (msg.a.a.a === 409)) {
						return A5(
							$author$project$Main$beginConflict,
							model,
							'leads',
							A2(
								$elm$core$Maybe$withDefault,
								0,
								A2(
									$elm$core$Maybe$map,
									A2(
										$elm$core$Basics$composeR,
										function ($) {
											return $.aO;
										},
										function ($) {
											return $.a9;
										}),
									model.x)),
							model.u,
							$author$project$Types$encodeUpdateLead(model.N));
					} else {
						var e = msg.a.a;
						return _Utils_Tuple2(
							model,
							A2(
								$author$project$Main$toast,
								'error',
								$author$project$Main$httpError(e)));
					}
				}
			case 67:
				var id = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$deleteLead, ctx, id, $author$project$State$DeleteLeadDone));
			case 68:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Lead deleted'),
									A2($author$project$Main$navigateTo, model.q, '/leads')
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 69:
				var id = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$advanceLead, ctx, id, $author$project$State$AdvanceDone));
			case 70:
				if (!msg.a.$) {
					var lead = msg.a.a;
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Advanced to ' + lead.$7),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 71:
				var id = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$convertLead, ctx, id, $author$project$State$ConvertDone));
			case 72:
				if (!msg.a.$) {
					var client = msg.a.a;
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Converted to client ' + client.bV),
									A2(
									$author$project$Main$navigateTo,
									model.q,
									'/clients/' + $elm$core$String$fromInt(client.a9))
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 73:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aS: v}),
					$elm$core$Platform$Cmd$none);
			case 74:
				var id = msg.a;
				return ($elm$core$String$trim(model.aS) === '') ? _Utils_Tuple2(model, $elm$core$Platform$Cmd$none) : _Utils_Tuple2(
					model,
					A4($author$project$Api$addNote, ctx, id, model.aS, $author$project$State$NoteDone));
			case 75:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{aS: ''}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Note added'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 76:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{c8: 0, dc: v}),
					A2(
						$elm$core$Task$perform,
						function (_v21) {
							return A2($author$project$State$SearchReady, 'leads', v);
						},
						$elm$core$Process$sleep(300)));
			case 77:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{cS: v, c7: true, c8: 0}),
					A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						_Utils_update(
							model,
							{cS: v}),
						0,
						A2(
							$author$project$Main$acceptLoad,
							_Utils_update(
								model,
								{cS: v, c8: 0}),
							$author$project$State$LeadsLoaded)));
			case 78:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{cQ: v, c7: true, c8: 0}),
					A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						_Utils_update(
							model,
							{cQ: v}),
						0,
						A2(
							$author$project$Main$acceptLoad,
							_Utils_update(
								model,
								{cQ: v, c8: 0}),
							$author$project$State$LeadsLoaded)));
			case 79:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{cR: v, c7: true, c8: 0}),
					A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						_Utils_update(
							model,
							{cR: v}),
						0,
						A2(
							$author$project$Main$acceptLoad,
							_Utils_update(
								model,
								{cR: v, c8: 0}),
							$author$project$State$LeadsLoaded)));
			case 80:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{c7: true, c8: 0, dm: v}),
					A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						_Utils_update(
							model,
							{dm: v}),
						0,
						A2(
							$author$project$Main$acceptLoad,
							_Utils_update(
								model,
								{c8: 0, dm: v}),
							$author$project$State$LeadsLoaded)));
			case 81:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{c8: 0, dl: !model.dl}),
					A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						_Utils_update(
							model,
							{dl: !model.dl}),
						0,
						A2(
							$author$project$Main$acceptLoad,
							_Utils_update(
								model,
								{c8: 0, dl: !model.dl}),
							$author$project$State$LeadsLoaded)));
			case 82:
				var next = _Utils_update(
					model,
					{cQ: 'All', cR: 'All', cS: 'All', c7: true, c8: 0, dc: '', v: $elm$core$Set$empty});
				return _Utils_Tuple2(
					next,
					A4(
						$author$project$Api$fetchFilteredLeads,
						ctx,
						next,
						0,
						A2($author$project$Main$acceptLoad, next, $author$project$State$LeadsLoaded)));
			case 83:
				var id = msg.a;
				var flag = msg.b;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							v: flag ? A2($elm$core$Set$insert, id, model.v) : A2($elm$core$Set$remove, id, model.v)
						}),
					$elm$core$Platform$Cmd$none);
			case 84:
				var flag = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							v: flag ? $elm$core$Set$fromList(
								A2(
									$elm$core$List$map,
									function ($) {
										return $.a9;
									},
									$author$project$Views$filteredLeads(model))) : $elm$core$Set$empty
						}),
					$elm$core$Platform$Cmd$none);
			case 85:
				return _Utils_Tuple2(
					model,
					A3(
						$author$project$Api$bulkLeads,
						ctx,
						{
							a2: $elm$core$Maybe$Nothing,
							ba: $elm$core$Set$toList(model.v),
							bi: 'advance'
						},
						$author$project$State$BulkDone));
			case 86:
				var userIdStr = msg.a;
				var _v22 = $elm$core$String$toInt(userIdStr);
				if (_v22.$ === 1) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					var uid = _v22.a;
					return _Utils_Tuple2(
						model,
						A3(
							$author$project$Api$bulkLeads,
							ctx,
							{
								a2: $elm$core$Maybe$Just(uid),
								ba: $elm$core$Set$toList(model.v),
								bi: 'assign'
							},
							$author$project$State$BulkDone));
				}
			case 87:
				return _Utils_Tuple2(
					model,
					A3(
						$author$project$Api$bulkLeads,
						ctx,
						{
							a2: $elm$core$Maybe$Nothing,
							ba: $elm$core$Set$toList(model.v),
							bi: 'delete'
						},
						$author$project$State$BulkDone));
			case 88:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{v: $elm$core$Set$empty}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Bulk action applied'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 89:
				var id = msg.a;
				var status = msg.b;
				var allTasks = _Utils_ap(
					model.J,
					_Utils_ap(
						A2(
							$elm$core$Maybe$withDefault,
							_List_Nil,
							A2(
								$elm$core$Maybe$map,
								function ($) {
									return $.J;
								},
								model.x)),
						A2(
							$elm$core$Maybe$withDefault,
							_List_Nil,
							A2(
								$elm$core$Maybe$map,
								function ($) {
									return $.J;
								},
								model.cC))));
				var revision = A2(
					$elm$core$Maybe$withDefault,
					0,
					A2(
						$elm$core$Maybe$map,
						function ($) {
							return $.m;
						},
						$elm$core$List$head(
							A2(
								$elm$core$List$filter,
								function (task) {
									return _Utils_eq(task.a9, id);
								},
								allTasks))));
				return _Utils_Tuple2(
					model,
					A5($author$project$Api$setTaskStatus, ctx, id, revision, status, $author$project$State$TaskStatusDone));
			case 90:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Task updated'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 91:
				var id = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$deleteTask, ctx, id, $author$project$State$TaskDeleteDone));
			case 92:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Task deleted'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 93:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{k: $author$project$State$emptyAddTask, bo: !model.bo}),
					$elm$core$Platform$Cmd$none);
			case 94:
				var f = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							k: f(model.k)
						}),
					$elm$core$Platform$Cmd$none);
			case 95:
				var leadId = msg.a;
				return A3($author$project$Main$submitTask, model, ctx, leadId);
			case 96:
				var cid = msg.a;
				return _Utils_Tuple2(
					model,
					A3(
						$author$project$Api$createTask,
						ctx,
						A2($author$project$Main$clientTaskBody, model, cid),
						$author$project$State$AddTaskDone));
			case 97:
				if (A2($elm$core$String$startsWith, 'client:', model.k.aP)) {
					var cid = A2(
						$elm$core$Maybe$withDefault,
						0,
						$elm$core$String$toInt(
							A2($elm$core$String$dropLeft, 7, model.k.aP)));
					return _Utils_Tuple2(
						model,
						A3(
							$author$project$Api$createTask,
							ctx,
							A2($author$project$Main$clientTaskBody, model, cid),
							$author$project$State$AddTaskDone));
				} else {
					var _v23 = $elm$core$String$toInt(model.k.aP);
					if (_v23.$ === 1) {
						return _Utils_Tuple2(
							model,
							A2($author$project$Main$toast, 'error', 'Choose a lead or client first'));
					} else {
						var leadId = _v23.a;
						return A3($author$project$Main$submitTask, model, ctx, leadId);
					}
				}
			case 98:
				if (!msg.a.$) {
					var task = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{k: $author$project$State$emptyAddTask, bo: false}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Task created'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 99:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aG: v, c8: 0}),
					A2(
						$elm$core$Task$perform,
						function (_v24) {
							return A2($author$project$State$SearchReady, 'clients', v);
						},
						$elm$core$Process$sleep(300)));
			case 100:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aF: $elm$core$Maybe$Nothing, n: $author$project$State$emptyClientForm, au: true}),
					$elm$core$Platform$Cmd$none);
			case 144:
				var _v25 = model.cC;
				if (_v25.$ === 1) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					var cd = _v25.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								aF: $elm$core$Maybe$Just(cd.a0.a9),
								n: $author$project$State$clientFormOf(cd.a0),
								u: $author$project$Main$clientPayload(
									_Utils_update(
										model,
										{
											n: $author$project$State$clientFormOf(cd.a0)
										})),
								au: true
							}),
						$elm$core$Platform$Cmd$none);
				}
			case 101:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{au: false}),
					$elm$core$Platform$Cmd$none);
			case 102:
				var f = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							n: f(model.n)
						}),
					$elm$core$Platform$Cmd$none);
			case 103:
				var _v26 = model.aF;
				if (!_v26.$) {
					var cid = _v26.a;
					return _Utils_Tuple2(
						model,
						A4(
							$author$project$Api$updateClient,
							ctx,
							cid,
							$author$project$Main$clientPayload(model),
							$author$project$State$ClientUpdated));
				} else {
					return _Utils_Tuple2(
						model,
						A3(
							$author$project$Api$createClient,
							ctx,
							$author$project$Main$clientPayload(model),
							$author$project$State$ClientFormSaved));
				}
			case 105:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{au: false}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Client saved'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					if ((msg.a.a.$ === 3) && (msg.a.a.a === 409)) {
						return A5(
							$author$project$Main$beginConflict,
							model,
							'clients',
							A2($elm$core$Maybe$withDefault, 0, model.aF),
							model.u,
							$author$project$Main$clientPayload(model));
					} else {
						var e = msg.a.a;
						return _Utils_Tuple2(
							model,
							A2(
								$author$project$Main$toast,
								'error',
								$author$project$Main$httpError(e)));
					}
				}
			case 104:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{au: false}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Client saved'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 106:
				var id = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$deleteClient, ctx, id, $author$project$State$DeleteClientDone));
			case 107:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Client deleted'),
									A2($author$project$Main$navigateTo, model.q, '/clients')
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 108:
				var mcase = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							w: $elm$core$Maybe$Just(
								A2(
									$elm$core$Maybe$withDefault,
									$author$project$State$emptyCaseForm,
									A2($elm$core$Maybe$map, $author$project$State$caseFormOf, mcase))),
							u: A2(
								$elm$core$Maybe$withDefault,
								$elm$json$Json$Encode$null,
								A2(
									$elm$core$Maybe$map,
									A2($elm$core$Basics$composeR, $author$project$State$caseFormOf, $author$project$Main$casePayload),
									mcase))
						}),
					$elm$core$Platform$Cmd$none);
			case 109:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{w: $elm$core$Maybe$Nothing}),
					$elm$core$Platform$Cmd$none);
			case 110:
				var f = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							w: A2($elm$core$Maybe$map, f, model.w)
						}),
					$elm$core$Platform$Cmd$none);
			case 111:
				var clientId = msg.a;
				var _v27 = model.w;
				if (_v27.$ === 1) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					var cf = _v27.a;
					return _Utils_Tuple2(
						model,
						A4(
							$author$project$Api$upsertCase,
							ctx,
							clientId,
							A2(
								$author$project$Main$withRevision,
								cf.m,
								$author$project$Types$encodeCaseInput(
									{al: cf.al, cy: cf.cy, aI: cf.aI, aJ: cf.aJ, $7: cf.$7})),
							$author$project$State$CaseFormSaved));
				}
			case 112:
				if (!msg.a.$) {
					var cd = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								w: $elm$core$Maybe$Nothing,
								cC: $elm$core$Maybe$Just(cd)
							}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Case saved'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					if ((msg.a.a.$ === 3) && (msg.a.a.a === 409)) {
						return A5(
							$author$project$Main$beginConflict,
							model,
							'cases',
							A2(
								$elm$core$Maybe$withDefault,
								0,
								A2(
									$elm$core$Maybe$andThen,
									function ($) {
										return $.al;
									},
									model.w)),
							model.u,
							A2(
								$elm$core$Maybe$withDefault,
								$elm$json$Json$Encode$null,
								A2($elm$core$Maybe$map, $author$project$Main$casePayload, model.w)));
					} else {
						var e = msg.a.a;
						return _Utils_Tuple2(
							model,
							A2(
								$author$project$Main$toast,
								'error',
								$author$project$Main$httpError(e)));
					}
				}
			case 113:
				var caseId = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$deleteCase, ctx, caseId, $author$project$State$DeleteCaseDone));
			case 114:
				if (!msg.a.$) {
					var next = _Utils_update(
						model,
						{
							cT: A3(
								$elm$core$Dict$insert,
								'owner',
								$author$project$Main$ownerForUrl(model.a_),
								$author$project$Features$defaults(model.bb)),
							Z: $author$project$Main$ownerForUrl(model.a_)
						});
					return _Utils_Tuple2(
						next,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Case deleted'),
									$author$project$Main$reloadCurrent(next)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 115:
				var file = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							R: $elm$core$Maybe$Just(file)
						}),
					$elm$core$Platform$Cmd$none);
			case 116:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{R: $elm$core$Maybe$Nothing}),
					$elm$core$Platform$Cmd$none);
			case 117:
				var id = msg.a;
				var _v28 = model.R;
				if (_v28.$ === 1) {
					return _Utils_Tuple2(
						model,
						A2($author$project$Main$toast, 'error', 'Choose a file first'));
				} else {
					var file = _v28.a;
					return _Utils_Tuple2(
						model,
						A4($author$project$Api$uploadLeadDocument, ctx, id, file, $author$project$State$LeadDocUploaded));
				}
			case 118:
				var id = msg.a;
				var _v29 = model.R;
				if (_v29.$ === 1) {
					return _Utils_Tuple2(
						model,
						A2($author$project$Main$toast, 'error', 'Choose a file first'));
				} else {
					var file = _v29.a;
					return _Utils_Tuple2(
						model,
						A4($author$project$Api$uploadClientDocument, ctx, id, file, $author$project$State$ClientDocUploaded));
				}
			case 119:
				if (!msg.a.$) {
					var detail = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								x: $elm$core$Maybe$Just(detail),
								R: $elm$core$Maybe$Nothing
							}),
						A2($author$project$Main$toast, 'success', 'Document uploaded'));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 120:
				if (!msg.a.$) {
					var cd = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								cC: $elm$core$Maybe$Just(cd),
								R: $elm$core$Maybe$Nothing
							}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Document uploaded for malware scanning'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 121:
				var id = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$deleteDocument, ctx, id, $author$project$State$DocDeleteDone));
			case 122:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'Document deleted'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 123:
				var file = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aU: $elm$core$Maybe$Just(file)
						}),
					$elm$core$Platform$Cmd$none);
			case 124:
				var _v30 = model.aU;
				if (_v30.$ === 1) {
					return _Utils_Tuple2(
						model,
						A2($author$project$Main$toast, 'error', 'Choose a CSV file first'));
				} else {
					var file = _v30.a;
					return _Utils_Tuple2(
						model,
						A3($author$project$Api$importLeads, ctx, file, $author$project$State$LeadsImported));
				}
			case 125:
				if (!msg.a.$) {
					var res = msg.a.a;
					var failureSummary = A2(
						$elm$core$String$join,
						'; ',
						A2(
							$elm$core$List$map,
							function (fe) {
								return 'row ' + ($elm$core$String$fromInt(fe.dh) + (': ' + fe.cO));
							},
							A2($elm$core$List$take, 3, res.bG)));
					var failCount = $elm$core$List$length(res.bG);
					var failToast = (!failCount) ? $elm$core$Platform$Cmd$none : A2(
						$author$project$Main$toast,
						'error',
						'Rows failed (' + ($elm$core$String$fromInt(failCount) + (') — ' + failureSummary)));
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{aU: $elm$core$Maybe$Nothing}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2(
									$author$project$Main$toast,
									'success',
									'Imported ' + ($elm$core$String$fromInt(res.bO) + (' lead' + ((res.bO === 1) ? '' : 's')))),
									failToast,
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 126:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{af: true, B: $author$project$State$emptyUserForm}),
					$elm$core$Platform$Cmd$none);
			case 127:
				var uid = msg.a;
				var _v31 = A2(
					$elm$core$List$filter,
					function (u) {
						return _Utils_eq(u.a9, uid);
					},
					model.T);
				if (_v31.b) {
					var u = _v31.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								u: $elm$json$Json$Encode$object(
									_List_fromArray(
										[
											_Utils_Tuple2(
											'uuName',
											$elm$json$Json$Encode$string(u.t)),
											_Utils_Tuple2(
											'uuRole',
											$elm$json$Json$Encode$string(u.aX))
										])),
								af: true,
								B: $author$project$State$userFormOf(u)
							}),
						$elm$core$Platform$Cmd$none);
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 128:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{af: false}),
					$elm$core$Platform$Cmd$none);
			case 129:
				var f = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							B: f(model.B)
						}),
					$elm$core$Platform$Cmd$none);
			case 130:
				var f = model.B;
				var _v32 = f.ch;
				if (_v32.$ === 1) {
					return ((f.ab !== '') && ($elm$core$String$length(f.ab) < 12)) ? _Utils_Tuple2(
						model,
						A2($author$project$Main$toast, 'error', 'Password must be at least 12 characters')) : _Utils_Tuple2(
						model,
						A3(
							$author$project$Api$createUser,
							ctx,
							$author$project$Types$encodeNewUser(
								{ap: f.ap, t: f.t, ab: f.ab, aX: f.aX}),
							$author$project$State$UserSaved));
				} else {
					var uid = _v32.a;
					return _Utils_Tuple2(
						model,
						A4(
							$author$project$Api$updateUser,
							ctx,
							uid,
							A2(
								$author$project$Main$withRevision,
								f.m,
								$author$project$Types$encodeUpdateUser(
									{t: f.t, ab: f.ab, aX: f.aX})),
							$author$project$State$UserUpdatedDone));
				}
			case 131:
				if (!msg.a.$) {
					var u = msg.a.a;
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{
								af: false,
								T: _Utils_ap(
									model.T,
									_List_fromArray(
										[u]))
							}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'User ' + (u.t + ' created')),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 132:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{af: false}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'User saved'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					if ((msg.a.a.$ === 3) && (msg.a.a.a === 409)) {
						return A5(
							$author$project$Main$beginConflict,
							model,
							'users',
							A2($elm$core$Maybe$withDefault, 0, model.B.ch),
							model.u,
							$elm$json$Json$Encode$object(
								_List_fromArray(
									[
										_Utils_Tuple2(
										'uuName',
										$elm$json$Json$Encode$string(model.B.t)),
										_Utils_Tuple2(
										'uuRole',
										$elm$json$Json$Encode$string(model.B.aX))
									])));
					} else {
						var e = msg.a.a;
						return _Utils_Tuple2(
							model,
							A2(
								$author$project$Main$toast,
								'error',
								$author$project$Main$httpError(e)));
					}
				}
			case 133:
				var uid = msg.a;
				return _Utils_Tuple2(
					model,
					A3($author$project$Api$deleteUser, ctx, uid, $author$project$State$DeleteUserDone));
			case 134:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						model,
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Main$toast, 'success', 'User deleted'),
									$author$project$Main$reloadCurrent(model)
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 135:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aV: '', aW: '', ac: '', aY: !model.aY}),
					$elm$core$Platform$Cmd$none);
			case 136:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aW: v}),
					$elm$core$Platform$Cmd$none);
			case 137:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{ac: v}),
					$elm$core$Platform$Cmd$none);
			case 138:
				var v = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aV: v}),
					$elm$core$Platform$Cmd$none);
			case 139:
				var validationError = ($elm$core$String$length(model.ac) < 12) ? 'New password must be at least 12 characters' : ((!_Utils_eq(model.ac, model.aV)) ? 'Passwords do not match' : '');
				return (validationError !== '') ? _Utils_Tuple2(
					model,
					A2($author$project$Main$toast, 'error', validationError)) : _Utils_Tuple2(
					model,
					A4($author$project$Api$changePassword, ctx, model.aW, model.ac, $author$project$State$PasswordChangeDone));
			case 140:
				if (!msg.a.$) {
					return _Utils_Tuple2(
						_Utils_update(
							model,
							{aQ: 'Your password was updated. Sign in with your new password.', aV: '', aW: '', ac: '', aY: false}),
						$elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									A2($author$project$Api$logout, ctx, $author$project$State$LogoutDone),
									A2($author$project$Main$toast, 'success', 'Password updated. Sign in again.')
								])));
				} else {
					var e = msg.a.a;
					return _Utils_Tuple2(
						model,
						A2(
							$author$project$Main$toast,
							'error',
							$author$project$Main$httpError(e)));
				}
			case 141:
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aT: !model.aT}),
					$elm$core$Platform$Cmd$none);
			case 142:
				var path = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{aT: false, j: ''}),
					_Utils_eq(path, model.a_.A) ? $author$project$Main$reloadCurrent(model) : A2($elm$browser$Browser$Navigation$pushUrl, model.q, path));
			case 145:
				var kind = msg.a;
				var textMsg = msg.b;
				return A3($author$project$Main$pushToast, model, kind, textMsg);
			default:
				var id = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aZ: A2(
								$elm$core$List$filter,
								function (t) {
									return !_Utils_eq(t.a9, id);
								},
								model.aZ)
						}),
					$elm$core$Platform$Cmd$none);
		}
	});
var $author$project$State$ConfirmAccepted = {$: 2};
var $author$project$State$ConfirmDismissed = {$: 3};
var $author$project$State$NavigateTo = function (a) {
	return {$: 142, a: a};
};
var $elm$html$Html$a = _VirtualDom_node('a');
var $elm$virtual_dom$VirtualDom$attribute = F2(
	function (key, value) {
		return A2(
			_VirtualDom_attribute,
			_VirtualDom_noOnOrFormAction(key),
			_VirtualDom_noJavaScriptOrHtmlUri(value));
	});
var $elm$html$Html$Attributes$attribute = $elm$virtual_dom$VirtualDom$attribute;
var $elm$html$Html$button = _VirtualDom_node('button');
var $elm$html$Html$Attributes$stringProperty = F2(
	function (key, string) {
		return A2(
			_VirtualDom_property,
			key,
			$elm$json$Json$Encode$string(string));
	});
var $elm$html$Html$Attributes$class = $elm$html$Html$Attributes$stringProperty('className');
var $author$project$State$ConfirmRequested = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $author$project$State$ConflictDismiss = {$: 22};
var $author$project$State$ConflictRebase = {$: 21};
var $author$project$State$ConflictUseCurrent = function (a) {
	return {$: 23, a: a};
};
var $elm$html$Html$caption = _VirtualDom_node('caption');
var $elm$html$Html$div = _VirtualDom_node('div');
var $elm$core$String$fromList = _String_fromList;
var $elm$core$Char$toLower = _Char_toLower;
var $author$project$Features$fieldLabel = function (key) {
	switch (key) {
		case 'ncFullName':
			return 'Client name';
		case 'ncEmail':
			return 'Email';
		case 'ncPhone':
			return 'Phone';
		case 'ncCaseOfficer':
			return 'Case officer';
		case 'ciServiceCategory':
			return 'Service';
		case 'ciDestination':
			return 'Destination';
		case 'ciStage':
			return 'Case stage';
		case 'ciNextDeadline':
			return 'Deadline';
		case 'ulFullName':
			return 'Lead name';
		case 'ulConsultantId':
			return 'Consultant';
		case 'uuName':
			return 'Staff name';
		case 'uuRole':
			return 'Role';
		case 'ageDays':
			return 'Age (days)';
		case 'overdueDays':
			return 'Overdue (days)';
		case 'averageAgeDays':
			return 'Average days in stage';
		case 'oldestDays':
			return 'Longest time in stage (days)';
		case 'openTasks':
			return 'Open tasks';
		case 'overdueTasks':
			return 'Overdue tasks';
		case 'openCases':
			return 'Open cases';
		case 'scanStatus':
			return 'Malware scan';
		case 'expiryWarning':
			return 'Expiry warning';
		case 'expiresOn':
			return 'Expires';
		case 'lastError':
			return 'Last error';
		case 'nextAttempt':
			return 'Next attempt';
		case 'sentAt':
			return 'Accepted at';
		default:
			return $elm$core$String$trim(
				$elm$core$String$fromList(
					A2(
						$elm$core$List$concatMap,
						function (c) {
							return $elm$core$Char$isUpper(c) ? _List_fromArray(
								[
									' ',
									$elm$core$Char$toLower(c)
								]) : _List_fromArray(
								[c]);
						},
						$elm$core$String$toList(key))));
	}
};
var $elm$core$List$isEmpty = function (xs) {
	if (!xs.b) {
		return true;
	} else {
		return false;
	}
};
var $elm$html$Html$h3 = _VirtualDom_node('h3');
var $elm$html$Html$Attributes$tabindex = function (n) {
	return A2(
		_VirtualDom_attribute,
		'tabIndex',
		$elm$core$String$fromInt(n));
};
var $elm$virtual_dom$VirtualDom$text = _VirtualDom_text;
var $elm$html$Html$text = $elm$virtual_dom$VirtualDom$text;
var $author$project$Ui$modal = F2(
	function (title, content) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('modal-overlay')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('modal-content'),
							A2($elm$html$Html$Attributes$attribute, 'role', 'dialog'),
							A2($elm$html$Html$Attributes$attribute, 'aria-modal', 'true'),
							A2($elm$html$Html$Attributes$attribute, 'aria-label', title),
							$elm$html$Html$Attributes$tabindex(-1)
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('section-head')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h3,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(title)
										]))
								])),
							content
						]))
				]));
	});
var $elm$virtual_dom$VirtualDom$Normal = function (a) {
	return {$: 0, a: a};
};
var $elm$virtual_dom$VirtualDom$on = _VirtualDom_on;
var $elm$html$Html$Events$on = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$Normal(decoder));
	});
var $elm$html$Html$Events$onClick = function (msg) {
	return A2(
		$elm$html$Html$Events$on,
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$html$Html$p = _VirtualDom_node('p');
var $elm$html$Html$Attributes$scope = $elm$html$Html$Attributes$stringProperty('scope');
var $elm$html$Html$table = _VirtualDom_node('table');
var $elm$html$Html$tbody = _VirtualDom_node('tbody');
var $elm$html$Html$td = _VirtualDom_node('td');
var $elm$html$Html$th = _VirtualDom_node('th');
var $elm$html$Html$thead = _VirtualDom_node('thead');
var $elm$html$Html$tr = _VirtualDom_node('tr');
var $author$project$Features$conflictView = function (model) {
	var workflow = A2(
		$elm$core$List$member,
		model.cE,
		_List_fromArray(
			['tasks', 'documents', 'reminders']));
	var latest = $author$project$Features$formValues(model.bz);
	var hidden = function (key) {
		return A2(
			$elm$core$List$member,
			key,
			_List_fromArray(
				['id', 'revision', 'expectedRevision', 'request', 'session', 'user', 'password', 'uuPassword']));
	};
	var get = F2(
		function (values_, key) {
			return A2(
				$elm$core$Maybe$withDefault,
				'',
				A2($elm$core$Dict$get, key, values_));
		});
	var changed = A2(
		$elm$core$List$filter,
		function (key) {
			return (!hidden(key)) && (!_Utils_eq(
				A2(get, model.bA, key),
				A2(get, latest, key)));
		},
		$elm$core$Dict$keys(latest));
	var cell_ = F2(
		function (values_, key) {
			return A2(
				$elm$html$Html$td,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(
						A2(get, values_, key))
					]));
		});
	return _Utils_eq(
		$elm$core$Maybe$Nothing,
		$elm$core$Result$toMaybe(
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, 'revision', $elm$json$Json$Decode$int),
				model.bz))) ? $elm$html$Html$text('') : A2(
		$author$project$Ui$modal,
		'Review changes before saving',
		A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$p,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Your save was rejected because this record changed. Review the original, your draft and the latest version. Accepting a version does not submit the form.')
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('table-scroll')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$table,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('data-table')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$caption,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text('Fields changed since the form was opened')
										])),
									A2(
									$elm$html$Html$thead,
									_List_Nil,
									_List_fromArray(
										[
											A2(
											$elm$html$Html$tr,
											_List_Nil,
											A2(
												$elm$core$List$map,
												function (labelText) {
													return A2(
														$elm$html$Html$th,
														_List_fromArray(
															[
																$elm$html$Html$Attributes$scope('col')
															]),
														_List_fromArray(
															[
																$elm$html$Html$text(labelText)
															]));
												},
												_List_fromArray(
													['Field', 'Original', 'Your draft', 'Latest', 'Action'])))
										])),
									A2(
									$elm$html$Html$tbody,
									_List_Nil,
									A2(
										$elm$core$List$map,
										function (key) {
											return A2(
												$elm$html$Html$tr,
												_List_Nil,
												_List_fromArray(
													[
														A2(
														$elm$html$Html$th,
														_List_fromArray(
															[
																$elm$html$Html$Attributes$scope('row')
															]),
														_List_fromArray(
															[
																$elm$html$Html$text(
																$author$project$Features$fieldLabel(key))
															])),
														A2(cell_, model.bA, key),
														A2(cell_, model.cD, key),
														A2(cell_, latest, key),
														A2(
														$elm$html$Html$td,
														_List_Nil,
														_List_fromArray(
															[
																workflow ? A2(
																$elm$html$Html$button,
																_List_fromArray(
																	[
																		$elm$html$Html$Attributes$class('btn btn-outline'),
																		$elm$html$Html$Events$onClick(
																		$author$project$State$ConflictUseCurrent(key))
																	]),
																_List_fromArray(
																	[
																		$elm$html$Html$text('Use latest value')
																	])) : $elm$html$Html$text('Review in your form')
															]))
													]));
										},
										changed))
								]))
						])),
					A2(
					$elm$html$Html$p,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							$elm$core$List$isEmpty(changed) ? 'The revision changed because related work changed. Your fields are unchanged in the latest version.' : 'Keeping your draft can replace the latest values for these fields.')
						])),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-primary'),
							$elm$html$Html$Events$onClick(
							A2($author$project$State$ConfirmRequested, 'Use the latest version number with the reviewed draft? Save the form separately when ready.', $author$project$State$ConflictRebase))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Accept comparison and return to form')
						])),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-outline'),
							$elm$html$Html$Events$onClick($author$project$State$ConflictDismiss)
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Keep reviewing later')
						]))
				])));
};
var $author$project$State$LogoutClicked = {$: 49};
var $author$project$State$ToggleDarkMode = {$: 43};
var $author$project$State$TogglePwModal = {$: 135};
var $elm$core$String$concat = function (strings) {
	return A2($elm$core$String$join, '', strings);
};
var $elm$core$String$toUpper = _String_toUpper;
var $elm$core$String$words = _String_words;
var $author$project$Ui$initials = function (name) {
	return $elm$core$String$toUpper(
		$elm$core$String$concat(
			A2(
				$elm$core$List$map,
				$elm$core$String$left(1),
				A2(
					$elm$core$List$take,
					2,
					$elm$core$String$words(name)))));
};
var $elm$html$Html$span = _VirtualDom_node('span');
var $author$project$Ui$avatar = function (name) {
	return A2(
		$elm$html$Html$span,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('avatar'),
				A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true')
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(
				$author$project$Ui$initials(name))
			]));
};
var $elm$html$Html$details = _VirtualDom_node('details');
var $elm$html$Html$Attributes$href = function (url) {
	return A2(
		$elm$html$Html$Attributes$stringProperty,
		'href',
		_VirtualDom_noJavaScriptUri(url));
};
var $elm$virtual_dom$VirtualDom$nodeNS = F2(
	function (namespace, tag) {
		return A2(
			_VirtualDom_nodeNS,
			namespace,
			_VirtualDom_noScript(tag));
	});
var $author$project$Ui$icon = function (name) {
	var paths = function () {
		switch (name) {
			case 'dashboard':
				return _List_fromArray(
					['M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z']);
			case 'leads':
				return _List_fromArray(
					['M4 4h16v4l-6 6v6l-4-2v-4L4 8z']);
			case 'clients':
				return _List_fromArray(
					['M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M16 3a4 4 0 0 1 0 8M22 21v-2a4 4 0 0 0-3-3.87', 'M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0']);
			case 'tasks':
				return _List_fromArray(
					['M9 5H5v16h14V5h-4M9 3h6v4H9zM8 12l2 2 6-5M8 18h8']);
			case 'reminders':
				return _List_fromArray(
					['M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4']);
			case 'duplicates':
				return _List_fromArray(
					['M9 9h12v12H9zM15 5V3H3v12h2']);
			case 'archive':
				return _List_fromArray(
					['M3 3h18v5H3zM5 8v13h14V8M10 12h4']);
			case 'system':
				return _List_fromArray(
					['M3 12h4l3-8 4 16 3-8h4']);
			case 'audit':
				return _List_fromArray(
					['M14 2H6v20h12V6zM14 2v5h5M9 12h6M9 16h6']);
			case 'search':
				return _List_fromArray(
					['M21 21l-5-5', 'M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0']);
			case 'arrow':
				return _List_fromArray(
					['M5 12h14M13 6l6 6-6 6']);
			case 'clock':
				return _List_fromArray(
					['M12 8v5l3 2', 'M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0']);
			case 'check':
				return _List_fromArray(
					['M5 12l4 4L19 6']);
			case 'plus':
				return _List_fromArray(
					['M12 5v14M5 12h14']);
			default:
				return _List_fromArray(
					['M12 3v18M3 12h18']);
		}
	}();
	return A4(
		$elm$virtual_dom$VirtualDom$nodeNS,
		'http://www.w3.org/2000/svg',
		'svg',
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$attribute, 'viewBox', '0 0 24 24'),
				A2($elm$html$Html$Attributes$attribute, 'width', '18'),
				A2($elm$html$Html$Attributes$attribute, 'height', '18'),
				A2($elm$html$Html$Attributes$attribute, 'fill', 'none'),
				A2($elm$html$Html$Attributes$attribute, 'stroke', 'currentColor'),
				A2($elm$html$Html$Attributes$attribute, 'stroke-width', '1.6'),
				A2($elm$html$Html$Attributes$attribute, 'stroke-linecap', 'round'),
				A2($elm$html$Html$Attributes$attribute, 'stroke-linejoin', 'round'),
				A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true'),
				A2($elm$html$Html$Attributes$attribute, 'focusable', 'false'),
				A2($elm$html$Html$Attributes$attribute, 'class', 'ui-icon')
			]),
		A2(
			$elm$core$List$map,
			function (path) {
				return A4(
					$elm$virtual_dom$VirtualDom$nodeNS,
					'http://www.w3.org/2000/svg',
					'path',
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$attribute, 'd', path)
						]),
					_List_Nil);
			},
			paths));
};
var $elm$html$Html$nav = _VirtualDom_node('nav');
var $elm$html$Html$strong = _VirtualDom_node('strong');
var $elm$html$Html$summary = _VirtualDom_node('summary');
var $author$project$Main$headerBar = function (model) {
	var user_ = A2(
		$elm$core$Maybe$withDefault,
		{ap: '', a9: 0, bf: false, t: '', m: 1, aX: ''},
		model.a$);
	var current = model.a_.A;
	var isActive = function (path) {
		return (path === '/') ? (current === '/') : A2($elm$core$String$startsWith, path, current);
	};
	var navBtn = F2(
		function (path, label) {
			return A2(
				$elm$html$Html$a,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class(
						isActive(path) ? 'nav-link active' : 'nav-link'),
						$elm$html$Html$Attributes$href(path),
						A2(
						$elm$html$Html$Attributes$attribute,
						'aria-current',
						isActive(path) ? 'page' : 'false')
					]),
				_List_fromArray(
					[
						$author$project$Ui$icon(
						(path === '/') ? 'dashboard' : ((path === '/users') ? 'clients' : A2($elm$core$String$dropLeft, 1, path))),
						A2(
						$elm$html$Html$span,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(label)
							]))
					]));
		});
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('header')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('logo')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('logo-icon')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('E')
							])),
						A2(
						$elm$html$Html$strong,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('ECC CRM')
							]))
					])),
				A2(
				$elm$html$Html$nav,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('nav'),
						A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Main navigation')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('nav-group')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('nav-section-label')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('WORKSPACE')
									])),
								A2(navBtn, '/', 'Dashboard'),
								A2(navBtn, '/leads', 'Leads'),
								A2(navBtn, '/clients', 'Clients'),
								A2(navBtn, '/tasks', 'Tasks')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('nav-group')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('nav-section-label')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('KEEP ON TRACK')
									])),
								A2(navBtn, '/reminders', 'Reminders'),
								A2(navBtn, '/duplicates', 'Duplicates')
							])),
						(user_.aX === 'admin') ? A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('nav-group')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('nav-section-label')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('MANAGE')
									])),
								A2(navBtn, '/users', 'Team'),
								A2(navBtn, '/archive', 'Archive'),
								A2(navBtn, '/system', 'System'),
								A2(navBtn, '/audit', 'Audit')
							])) : A2($elm$html$Html$span, _List_Nil, _List_Nil)
					])),
				A2(
				$elm$html$Html$details,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('workspace-tools')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$summary,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('Workspace tools')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('tools-menu')
							]),
						A2(
							$elm$core$List$map,
							function (_v0) {
								var section = _v0.a;
								var labelText = _v0.b;
								return A2(
									$elm$html$Html$a,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$href('/work/' + section),
											$elm$html$Html$Attributes$class('nav-link')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(labelText)
										]));
							},
							_Utils_ap(
								_List_fromArray(
									[
										_Utils_Tuple2('tasks', 'Edit and assign tasks'),
										_Utils_Tuple2('history', 'Client/case history'),
										_Utils_Tuple2('documents', 'Document checklists'),
										_Utils_Tuple2('reminders', 'Email reminders'),
										_Utils_Tuple2('search', 'Search and saved views'),
										_Utils_Tuple2('appointments', 'Appointments'),
										_Utils_Tuple2('communication', 'Email a contact'),
										_Utils_Tuple2('portal', 'Client portal'),
										_Utils_Tuple2('security', 'Account security'),
										_Utils_Tuple2('notifications', 'Notification centre'),
										_Utils_Tuple2('mail', 'Email delivery')
									]),
								(user_.aX === 'admin') ? _List_fromArray(
									[
										_Utils_Tuple2('merge', 'Merge duplicates'),
										_Utils_Tuple2('reports', 'Reports'),
										_Utils_Tuple2('invoices', 'Invoices'),
										_Utils_Tuple2('ageing', 'Case ageing'),
										_Utils_Tuple2('bottlenecks', 'Case bottlenecks'),
										_Utils_Tuple2('trends', 'Workload trends')
									]) : _List_Nil)))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('header-right')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
								$elm$html$Html$Events$onClick($author$project$State$TogglePwModal)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Password')
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn btn-sm btn-outline dark-toggle'),
								$elm$html$Html$Events$onClick($author$project$State$ToggleDarkMode)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								model.ao ? '☀ Light' : '☾ Dark')
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('user-chip')
							]),
						_List_fromArray(
							[
								$author$project$Ui$avatar(user_.t),
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('user-identity')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$strong,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(user_.t)
											])),
										A2(
										$elm$html$Html$span,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('user-role')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(user_.aX)
											]))
									]))
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn-logout'),
								$elm$html$Html$Events$onClick($author$project$State$LogoutClicked)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Log out')
							]))
					]))
			]));
};
var $elm$html$Html$Attributes$id = $elm$html$Html$Attributes$stringProperty('id');
var $author$project$State$LoginClicked = {$: 46};
var $author$project$State$LoginEmailChanged = function (a) {
	return {$: 44, a: a};
};
var $author$project$State$LoginModeChanged = function (a) {
	return {$: 4, a: a};
};
var $author$project$State$LoginOtpChanged = function (a) {
	return {$: 30, a: a};
};
var $author$project$State$LoginPasswordChanged = function (a) {
	return {$: 45, a: a};
};
var $author$project$State$RecoverClicked = {$: 5};
var $author$project$State$ResetClicked = {$: 6};
var $elm$html$Html$br = _VirtualDom_node('br');
var $elm$html$Html$Attributes$boolProperty = F2(
	function (key, bool) {
		return A2(
			_VirtualDom_property,
			key,
			$elm$json$Json$Encode$bool(bool));
	});
var $elm$html$Html$Attributes$disabled = $elm$html$Html$Attributes$boolProperty('disabled');
var $elm$html$Html$form = _VirtualDom_node('form');
var $elm$html$Html$h1 = _VirtualDom_node('h1');
var $elm$html$Html$h2 = _VirtualDom_node('h2');
var $elm$html$Html$Attributes$for = $elm$html$Html$Attributes$stringProperty('htmlFor');
var $elm$html$Html$input = _VirtualDom_node('input');
var $elm$html$Html$label = _VirtualDom_node('label');
var $elm$html$Html$Events$alwaysStop = function (x) {
	return _Utils_Tuple2(x, true);
};
var $elm$virtual_dom$VirtualDom$MayStopPropagation = function (a) {
	return {$: 1, a: a};
};
var $elm$html$Html$Events$stopPropagationOn = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$MayStopPropagation(decoder));
	});
var $elm$html$Html$Events$targetValue = A2(
	$elm$json$Json$Decode$at,
	_List_fromArray(
		['target', 'value']),
	$elm$json$Json$Decode$string);
var $elm$html$Html$Events$onInput = function (tagger) {
	return A2(
		$elm$html$Html$Events$stopPropagationOn,
		'input',
		A2(
			$elm$json$Json$Decode$map,
			$elm$html$Html$Events$alwaysStop,
			A2($elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetValue)));
};
var $elm$html$Html$Attributes$type_ = $elm$html$Html$Attributes$stringProperty('type');
var $elm$html$Html$Attributes$value = $elm$html$Html$Attributes$stringProperty('value');
var $author$project$Ui$inputField = F4(
	function (label, val, typ, onInputMsg) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('form-group')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$label,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$for(
							'field-' + $elm$core$String$toLower(
								A3($elm$core$String$replace, ' ', '-', label)))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label)
						])),
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$id(
							'field-' + $elm$core$String$toLower(
								A3($elm$core$String$replace, ' ', '-', label))),
							A2(
							$elm$html$Html$Attributes$attribute,
							'autocomplete',
							(typ === 'password') ? 'current-password' : ((typ === 'email') ? 'email' : 'off')),
							$elm$html$Html$Attributes$type_(typ),
							$elm$html$Html$Attributes$class('input'),
							$elm$html$Html$Attributes$value(val),
							$elm$html$Html$Events$onInput(onInputMsg)
						]),
					_List_Nil)
				]));
	});
var $elm$html$Html$Events$alwaysPreventDefault = function (msg) {
	return _Utils_Tuple2(msg, true);
};
var $elm$virtual_dom$VirtualDom$MayPreventDefault = function (a) {
	return {$: 2, a: a};
};
var $elm$html$Html$Events$preventDefaultOn = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$MayPreventDefault(decoder));
	});
var $elm$html$Html$Events$onSubmit = function (msg) {
	return A2(
		$elm$html$Html$Events$preventDefaultOn,
		'submit',
		A2(
			$elm$json$Json$Decode$map,
			$elm$html$Html$Events$alwaysPreventDefault,
			$elm$json$Json$Decode$succeed(msg)));
};
var $author$project$Views$loginView = function (model) {
	var resetting = model.bT === 'reset';
	var recovering = model.bT === 'recover';
	var subtitle = resetting ? 'Choose a new password for your account.' : (recovering ? 'We’ll email you a secure link to reset your password.' : 'Sign in to your client workspace.');
	var heading = resetting ? 'A fresh start.' : (recovering ? 'Let’s get you back in.' : 'Good to see you.');
	var action = resetting ? $author$project$State$ResetClicked : (recovering ? $author$project$State$RecoverClicked : $author$project$State$LoginClicked);
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('login-wrap')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('login-story')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('login-brand')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('logo-icon')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('E')
									])),
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('ECC')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('CLIENT WORKSPACE')
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('login-story-copy')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('eyebrow')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('BUILT AROUND PEOPLE')
									])),
								A2(
								$elm$html$Html$h1,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Every journey.'),
										A2($elm$html$Html$br, _List_Nil, _List_Nil),
										$elm$html$Html$text('A little clearer.')
									])),
								A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Keep your relationships, cases and next steps together. Make every client feel remembered.')
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('login-story-footer')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('A thoughtful way to work.')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('ECC / 01')
									]))
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('login-panel')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('login-card')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('eyebrow')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('YOUR WORK, CONNECTED')
									])),
								A2(
								$elm$html$Html$h2,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(heading)
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('login-sub')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(subtitle)
									])),
								A2(
								$elm$html$Html$form,
								_List_fromArray(
									[
										$elm$html$Html$Events$onSubmit(action)
									]),
								_List_fromArray(
									[
										resetting ? A2($elm$html$Html$span, _List_Nil, _List_Nil) : A4($author$project$Ui$inputField, 'Email address', model.bc, 'email', $author$project$State$LoginEmailChanged),
										recovering ? A2($elm$html$Html$span, _List_Nil, _List_Nil) : A4(
										$author$project$Ui$inputField,
										resetting ? 'New password · at least 12 characters' : 'Password',
										model.G,
										'password',
										$author$project$State$LoginPasswordChanged),
										(recovering || resetting) ? A2($elm$html$Html$span, _List_Nil, _List_Nil) : A4($author$project$Ui$inputField, 'Authenticator or recovery code (if enabled)', model.at, 'text', $author$project$State$LoginOtpChanged),
										(model.s !== '') ? A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('login-error'),
												A2($elm$html$Html$Attributes$attribute, 'role', 'alert')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(model.s)
											])) : A2($elm$html$Html$span, _List_Nil, _List_Nil),
										(model.aQ !== '') ? A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('notice-banner'),
												A2($elm$html$Html$Attributes$attribute, 'role', 'status')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(model.aQ)
											])) : A2($elm$html$Html$span, _List_Nil, _List_Nil),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('btn btn-primary login-submit'),
												$elm$html$Html$Attributes$type_('submit'),
												$elm$html$Html$Attributes$disabled(model.C)
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												model.C ? 'Please wait…' : (resetting ? 'Set new password →' : (recovering ? 'Send recovery link →' : 'Sign in →')))
											]))
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('text-button'),
										$elm$html$Html$Events$onClick(
										$author$project$State$LoginModeChanged(
											(recovering || resetting) ? 'login' : 'recover'))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										(recovering || resetting) ? '← Back to sign in' : 'Forgot your password?')
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('login-hint')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Need access? Ask your workspace administrator for an invitation.')
									]))
							]))
					]))
			]));
};
var $elm$html$Html$main_ = _VirtualDom_node('main');
var $author$project$Views$auditValueStr = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			$elm$json$Json$Decode$string,
			$elm$json$Json$Decode$null('—'),
			A2($elm$json$Json$Decode$map, $elm$core$String$fromInt, $elm$json$Json$Decode$int),
			A2(
			$elm$json$Json$Decode$map,
			function (b) {
				return b ? 'yes' : 'no';
			},
			$elm$json$Json$Decode$bool)
		]));
var $author$project$Views$changeEntry = A3(
	$elm$json$Json$Decode$map2,
	F2(
		function (from, to) {
			return from + (' → ' + to);
		}),
	A2($elm$json$Json$Decode$field, 'from', $author$project$Views$auditValueStr),
	A2($elm$json$Json$Decode$field, 'to', $author$project$Views$auditValueStr));
var $author$project$Views$changeLines = function (mv) {
	if (mv.$ === 1) {
		return _List_Nil;
	} else {
		var v = mv.a;
		var _v1 = A2(
			$elm$json$Json$Decode$decodeValue,
			$elm$json$Json$Decode$keyValuePairs($author$project$Views$changeEntry),
			v);
		if (!_v1.$) {
			var pairs = _v1.a;
			return A2(
				$elm$core$List$map,
				function (_v2) {
					var field = _v2.a;
					var diff = _v2.b;
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('activity-desc')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(field + (': ' + diff))
							]));
				},
				pairs);
		} else {
			return _List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('activity-desc')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('(unparsable change)')
						]))
				]);
		}
	}
};
var $author$project$Ui$emptyNote = function (msg) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('empty-note')
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(msg)
			]));
};
var $author$project$Views$entityHref = function (e) {
	var _v0 = e.cN;
	switch (_v0) {
		case 'lead':
			return $elm$core$Maybe$Just(
				'/leads/' + $elm$core$String$fromInt(e.cL));
		case 'client':
			return $elm$core$Maybe$Just(
				'/clients/' + $elm$core$String$fromInt(e.cL));
		default:
			return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Ui$fmtDateTime = function (iso) {
	return A3($elm$core$String$slice, 0, 10, iso);
};
var $author$project$Views$auditView = function (model) {
	var me_ = A2(
		$elm$core$Maybe$withDefault,
		{ap: '', a9: 0, bf: false, t: '', m: 1, aX: ''},
		model.a$);
	if (me_.aX !== 'admin') {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('card')
				]),
			_List_fromArray(
				[
					$author$project$Ui$emptyNote('Admin access required.')
				]));
	} else {
		var entityLink = function (e) {
			var _v0 = $author$project$Views$entityHref(e);
			if (!_v0.$) {
				var path = _v0.a;
				return A2(
					$elm$html$Html$a,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('tag tag-id'),
							$elm$html$Html$Attributes$href(path)
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							e.cN + (' #' + $elm$core$String$fromInt(e.cL)))
						]));
			} else {
				return A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('tag tag-id')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(e.cN)
						]));
			}
		};
		var actionTag = function (action) {
			return A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class(
						(action === 'deleted') ? 'tag tag-lost' : ((action === 'created') ? 'tag tag-converted' : 'tag tag-stage-blue'))
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(action)
					]));
		};
		var auditRow = function (e) {
			return A2(
				$elm$html$Html$tr,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(
								$author$project$Ui$fmtDateTime(e.W))
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(
								A2($elm$core$Maybe$withDefault, '—', e.cq))
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								actionTag(e.cp)
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(
								A2($elm$core$Maybe$withDefault, '', e.cM))
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								entityLink(e)
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						$author$project$Views$changeLines(e.cA))
					]));
		};
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('page-head')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h2,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text('Audit Trail')
										])),
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('empty-note')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Every lead and client edit and deletion, with before/after values.')
										]))
								]))
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('card table-card')
						]),
					_List_fromArray(
						[
							$elm$core$List$isEmpty(model.aD) ? $author$project$Ui$emptyNote('No changes recorded yet.') : A2(
							$elm$html$Html$table,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('data-table')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$thead,
									_List_Nil,
									_List_fromArray(
										[
											A2(
											$elm$html$Html$tr,
											_List_Nil,
											_List_fromArray(
												[
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('When')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Who')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Action')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Record')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Entity')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Changes')
														]))
												]))
										])),
									A2(
									$elm$html$Html$tbody,
									_List_Nil,
									A2($elm$core$List$map, auditRow, model.aD))
								]))
						]))
				]));
	}
};
var $author$project$State$DeleteCaseClicked = function (a) {
	return {$: 113, a: a};
};
var $author$project$State$DeleteClientConfirmed = function (a) {
	return {$: 106, a: a};
};
var $author$project$State$OpenCaseForm = function (a) {
	return {$: 108, a: a};
};
var $author$project$State$OpenClientEditor = function (a) {
	return {$: 144, a: a};
};
var $author$project$State$SubmitClientTask = function (a) {
	return {$: 96, a: a};
};
var $author$project$State$UploadClientDocClicked = function (a) {
	return {$: 118, a: a};
};
var $author$project$State$CloseCaseForm = {$: 109};
var $author$project$State$SubmitCaseForm = function (a) {
	return {$: 111, a: a};
};
var $author$project$State$UpdateCaseForm = function (a) {
	return {$: 110, a: a};
};
var $author$project$Types$caseStages = _List_fromArray(
	['Documents Under Review', 'Submitted', 'Decision Pending', 'Approved', 'Rejected']);
var $author$project$Types$destinations = _List_fromArray(
	['Canada', 'Australia', 'New Zealand', 'UAE', 'UK', 'Schengen']);
var $author$project$Views$isReadOnly = function (model) {
	return _Utils_eq(
		A2(
			$elm$core$Maybe$map,
			function ($) {
				return $.aX;
			},
			model.a$),
		$elm$core$Maybe$Just('viewer'));
};
var $elm$html$Html$option = _VirtualDom_node('option');
var $elm$html$Html$select = _VirtualDom_node('select');
var $elm$html$Html$Attributes$selected = $elm$html$Html$Attributes$boolProperty('selected');
var $author$project$Ui$selectField = F4(
	function (label, opts, current, onInputMsg) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('form-group')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$label,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$for(
							'field-' + $elm$core$String$toLower(
								A3($elm$core$String$replace, ' ', '-', label)))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label)
						])),
					A2(
					$elm$html$Html$select,
					_List_fromArray(
						[
							$elm$html$Html$Events$onInput(onInputMsg)
						]),
					A2(
						$elm$core$List$map,
						function (o) {
							return A2(
								$elm$html$Html$option,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$value(o),
										$elm$html$Html$Attributes$selected(
										_Utils_eq(o, current))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(o)
									]));
						},
						opts))
				]));
	});
var $author$project$Types$services = _List_fromArray(
	['Student Visa', 'Work Visa', 'Tourist Visa', 'Immigration Consultation', 'School Admission']);
var $elm$virtual_dom$VirtualDom$style = _VirtualDom_style;
var $elm$html$Html$Attributes$style = $elm$virtual_dom$VirtualDom$style;
var $author$project$Views$caseModal = F3(
	function (model, cf, cd) {
		return A2(
			$author$project$Ui$modal,
			_Utils_eq(cf.al, $elm$core$Maybe$Nothing) ? 'Add Case' : 'Edit Case',
			A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						A4(
						$author$project$Ui$selectField,
						'Service Category',
						$author$project$Types$services,
						cf.cy,
						function (v) {
							return $author$project$State$UpdateCaseForm(
								function (f) {
									return _Utils_update(
										f,
										{cy: v});
								});
						}),
						A4(
						$author$project$Ui$selectField,
						'Destination',
						$author$project$Types$destinations,
						cf.aJ,
						function (v) {
							return $author$project$State$UpdateCaseForm(
								function (f) {
									return _Utils_update(
										f,
										{aJ: v});
								});
						}),
						A4(
						$author$project$Ui$selectField,
						'Stage',
						$author$project$Types$caseStages,
						cf.$7,
						function (v) {
							return $author$project$State$UpdateCaseForm(
								function (f) {
									return _Utils_update(
										f,
										{$7: v});
								});
						}),
						A4(
						$author$project$Ui$inputField,
						'Next Deadline',
						cf.aI,
						'date',
						function (v) {
							return $author$project$State$UpdateCaseForm(
								function (f) {
									return _Utils_update(
										f,
										{aI: v});
								});
						}),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('flex'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$disabled(
										$author$project$Views$isReadOnly(model)),
										$elm$html$Html$Attributes$class('btn btn-primary'),
										$elm$html$Html$Events$onClick(
										$author$project$State$SubmitCaseForm(cd.a0.a9))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Save Case')
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Events$onClick($author$project$State$CloseCaseForm)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Cancel')
									]))
							]))
					])));
	});
var $author$project$State$DocPicked = function (a) {
	return {$: 115, a: a};
};
var $elm$file$File$decoder = _File_decoder;
var $author$project$State$DocDeleted = function (a) {
	return {$: 121, a: a};
};
var $author$project$Api$documentDownloadUrl = F2(
	function (ctx, id) {
		return ctx.M + ('/api/documents/' + ($elm$core$String$fromInt(id) + '/download'));
	});
var $elm$html$Html$Attributes$download = function (fileName) {
	return A2($elm$html$Html$Attributes$stringProperty, 'download', fileName);
};
var $author$project$Views$fmtSize = function (bytes) {
	return (bytes >= 1048576) ? ($elm$core$String$fromInt((bytes / 1048576) | 0) + ' MB') : ((bytes >= 1024) ? ($elm$core$String$fromInt((bytes / 1024) | 0) + ' KB') : ($elm$core$String$fromInt(bytes) + ' B'));
};
var $elm$html$Html$Attributes$title = $elm$html$Html$Attributes$stringProperty('title');
var $author$project$Views$documentRow = F2(
	function (model, d) {
		var ctx = {M: model.ak, du: model.du};
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('task-row')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$title(d.cU)
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$strong,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(d.cU)
								]))
						])),
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('activity-date')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							$author$project$Views$fmtSize(d.dk))
						])),
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('activity-date')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($elm$core$String$left, 10, d.W))
						])),
					A2(
					$elm$html$Html$span,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($elm$core$Maybe$withDefault, '', d.dA))
						])),
					(d.di !== 'Clean') ? A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('tag')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Scan: ' + d.di)
						])) : A2(
					$elm$html$Html$a,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
							$elm$html$Html$Attributes$href(
							A2($author$project$Api$documentDownloadUrl, ctx, d.a9)),
							$elm$html$Html$Attributes$download('')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Download')
						])),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$disabled(
							$author$project$Views$isReadOnly(model)),
							$elm$html$Html$Attributes$class('btn btn-sm btn-danger'),
							$elm$html$Html$Events$onClick(
							A2(
								$author$project$State$ConfirmRequested,
								'Delete this document? This action cannot be undone.',
								$author$project$State$DocDeleted(d.a9)))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Delete')
						]))
				]));
	});
var $author$project$Views$documentRows = F2(
	function (model, docs) {
		return $elm$core$List$isEmpty(docs) ? $author$project$Ui$emptyNote('No documents yet — upload a passport, form, or scan.') : A2(
			$elm$html$Html$div,
			_List_Nil,
			A2(
				$elm$core$List$map,
				$author$project$Views$documentRow(model),
				docs));
	});
var $elm$json$Json$Decode$index = _Json_decodeIndex;
var $elm$file$File$name = _File_name;
var $author$project$Views$documentsCard = F3(
	function (model, docs, uploadMsg) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('card')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('section-head')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$h3,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Documents')
								])),
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('lead-count')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									$elm$core$String$fromInt(
										$elm$core$List$length(docs)))
								]))
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('inline-form'),
							A2($elm$html$Html$Attributes$style, 'margin-bottom', '10px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$disabled(
									$author$project$Views$isReadOnly(model)),
									$elm$html$Html$Attributes$type_('file'),
									A2(
									$elm$html$Html$Events$on,
									'change',
									A2(
										$elm$json$Json$Decode$map,
										$author$project$State$DocPicked,
										A2(
											$elm$json$Json$Decode$at,
											_List_fromArray(
												['target', 'files']),
											A2($elm$json$Json$Decode$index, 0, $elm$file$File$decoder))))
								]),
							_List_Nil),
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('empty-note')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									function () {
										var _v0 = model.R;
										if (!_v0.$) {
											var file = _v0.a;
											return $elm$file$File$name(file);
										} else {
											return 'No file chosen';
										}
									}())
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$disabled(
									$author$project$Views$isReadOnly(model)),
									$elm$html$Html$Attributes$class('btn btn-sm btn-primary'),
									$elm$html$Html$Events$onClick(uploadMsg)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Upload')
								]))
						])),
					A2($author$project$Views$documentRows, model, docs)
				]));
	});
var $author$project$State$InlineOwner = function (a) {
	return {$: 17, a: a};
};
var $author$project$State$InlineSection = function (a) {
	return {$: 16, a: a};
};
var $author$project$State$PageStep = function (a) {
	return {$: 10, a: a};
};
var $author$project$State$ChecklistFile = function (a) {
	return {$: 18, a: a};
};
var $author$project$State$ChecklistUpload = F2(
	function (a, b) {
		return {$: 19, a: a, b: b};
	});
var $author$project$State$FeatureEdit = function (a) {
	return {$: 26, a: a};
};
var $author$project$State$FeatureField = F2(
	function (a, b) {
		return {$: 24, a: a, b: b};
	});
var $author$project$State$FeatureReset = {$: 27};
var $author$project$State$FeatureRun = function (a) {
	return {$: 28, a: a};
};
var $author$project$State$FeatureSearch = function (a) {
	return {$: 25, a: a};
};
var $author$project$Features$columns = function (section) {
	switch (section) {
		case 'tasks':
			return _List_fromArray(
				['recordName', 'assigneeName', 'status', 'priority', 'dueDate']);
		case 'history':
			return _List_fromArray(
				['actor', 'kind', 'date', 'note']);
		case 'documents':
			return _List_fromArray(
				['status', 'scanStatus', 'expiryWarning', 'expiresOn', 'reviewNote']);
		case 'mail':
			return _List_fromArray(
				['recipient', 'status', 'attempts', 'lastError', 'nextAttempt', 'sentAt']);
		case 'notifications':
			return _List_fromArray(
				['kind', 'status', 'date']);
		case 'ageing':
			return _List_fromArray(
				['stage', 'ageDays', 'overdueDays', 'staff']);
		case 'bottlenecks':
			return _List_fromArray(
				['cases', 'averageAgeDays', 'oldestDays']);
		case 'trends':
			return _List_fromArray(
				['date', 'openTasks', 'overdueTasks', 'openCases']);
		case 'reports':
			return _List_fromArray(
				['from', 'to', 'summary']);
		case 'security':
			return _List_fromArray(
				['created', 'expires']);
		case 'invoices':
			return _List_fromArray(
				['currency', 'amount', 'status', 'dueDate', 'description']);
		case 'appointments':
			return _List_fromArray(
				['startsAt', 'endsAt', 'location', 'status']);
		default:
			return _List_fromArray(
				['status', 'expires', 'kind', 'phone', 'email']);
	}
};
var $author$project$Features$fields = function (section) {
	switch (section) {
		case 'tasks':
			return _List_fromArray(
				[
					_Utils_Tuple3('Title', 'title', 'text'),
					_Utils_Tuple3('Description', 'description', 'textarea'),
					_Utils_Tuple3('Due date', 'dueDate', 'date'),
					_Utils_Tuple3('Priority', 'priority', 'Low|Medium|High|Urgent'),
					_Utils_Tuple3('Status', 'status', 'Pending|In Progress|Done'),
					_Utils_Tuple3('Assigned to', 'assignee', 'staff'),
					_Utils_Tuple3('Repeat every (days; blank for one time)', 'recurrenceDays', 'number')
				]);
		case 'history':
			return _List_fromArray(
				[
					_Utils_Tuple3('Record', 'owner', 'record'),
					_Utils_Tuple3('Note or conversation summary', 'note', 'textarea')
				]);
		case 'documents':
			return _List_fromArray(
				[
					_Utils_Tuple3('Record', 'owner', 'record'),
					_Utils_Tuple3('Required document', 'title', 'text'),
					_Utils_Tuple3('Required?', 'required', 'true|false'),
					_Utils_Tuple3('Review status', 'status', 'Missing|Received|Approved|Rejected'),
					_Utils_Tuple3('Expires on', 'expiresOn', 'date'),
					_Utils_Tuple3('Feedback for the client', 'reviewNote', 'textarea'),
					_Utils_Tuple3('Existing file to attach as a new version', 'document', 'document')
				]);
		case 'reminders':
			return _List_fromArray(
				[
					_Utils_Tuple3('Task', 'task', 'task'),
					_Utils_Tuple3('Days before deadline', 'daysBefore', 'number'),
					_Utils_Tuple3('Escalate to administrators after overdue days', 'escalateAfter', 'number'),
					_Utils_Tuple3('Email reminders enabled?', 'enabled', 'true|false')
				]);
		case 'merge':
			return _List_fromArray(
				[
					_Utils_Tuple3('Record type', 'entity', 'leads|clients'),
					_Utils_Tuple3('Source to archive', 'source', 'merge'),
					_Utils_Tuple3('Surviving record', 'target', 'merge'),
					_Utils_Tuple3('Type MERGE after reviewing the preview', 'confirmation', 'text')
				]);
		case 'reports':
			return _List_fromArray(
				[
					_Utils_Tuple3('From date', 'from', 'date'),
					_Utils_Tuple3('To date', 'to', 'date')
				]);
		case 'search':
			return _List_fromArray(
				[
					_Utils_Tuple3('View name', 'name', 'text'),
					_Utils_Tuple3('Records', 'entity', 'leads|clients|tasks|cases'),
					_Utils_Tuple3('Contains', 'query', 'text'),
					_Utils_Tuple3('Assigned to me?', 'mine', 'true|false'),
					_Utils_Tuple3('Overdue only?', 'overdue', 'true|false')
				]);
		case 'security':
			return _List_fromArray(
				[
					_Utils_Tuple3('Current password', 'password', 'password'),
					_Utils_Tuple3('Authenticator or recovery code', 'code', 'text')
				]);
		case 'appointments':
			return _List_fromArray(
				[
					_Utils_Tuple3('Record', 'owner', 'record'),
					_Utils_Tuple3('Appointment', 'title', 'text'),
					_Utils_Tuple3('Staff member', 'assignee', 'staff'),
					_Utils_Tuple3('Starts (UTC)', 'startsAt', 'datetime-local'),
					_Utils_Tuple3('Ends (UTC)', 'endsAt', 'datetime-local'),
					_Utils_Tuple3('Location or meeting link', 'location', 'text'),
					_Utils_Tuple3('Status', 'status', 'Scheduled|Completed|Cancelled')
				]);
		case 'invoices':
			return _List_fromArray(
				[
					_Utils_Tuple3('Client', 'owner', 'client'),
					_Utils_Tuple3('Description', 'description', 'textarea'),
					_Utils_Tuple3('Currency', 'currency', 'PHP|USD|EUR|GBP|AUD|CAD|NZD'),
					_Utils_Tuple3('Amount', 'amount', 'text'),
					_Utils_Tuple3('Due date', 'dueDate', 'date'),
					_Utils_Tuple3('Status', 'status', 'Draft|Issued|Paid|Void')
				]);
		case 'portal':
			return _List_fromArray(
				[
					_Utils_Tuple3('Client', 'owner', 'client'),
					_Utils_Tuple3('Access duration (days)', 'days', 'number'),
					_Utils_Tuple3('Approved file to share', 'document', 'document')
				]);
		case 'notifications':
			return _List_fromArray(
				[
					_Utils_Tuple3('Task assignments', 'assignments', 'true|false'),
					_Utils_Tuple3('Upcoming deadlines', 'deadlines', 'true|false'),
					_Utils_Tuple3('Document rejections', 'documents', 'true|false'),
					_Utils_Tuple3('Overdue escalation', 'escalations', 'true|false'),
					_Utils_Tuple3('Reminder emails', 'emailEnabled', 'true|false')
				]);
		case 'mail':
			return _List_Nil;
		case 'ageing':
			return _List_fromArray(
				[
					_Utils_Tuple3('Created from', 'from', 'date'),
					_Utils_Tuple3('Created to', 'to', 'date')
				]);
		case 'bottlenecks':
			return _List_fromArray(
				[
					_Utils_Tuple3('Created from', 'from', 'date'),
					_Utils_Tuple3('Created to', 'to', 'date')
				]);
		case 'trends':
			return _List_fromArray(
				[
					_Utils_Tuple3('From', 'from', 'date'),
					_Utils_Tuple3('To', 'to', 'date')
				]);
		case 'communication':
			return _List_fromArray(
				[
					_Utils_Tuple3('Contact record', 'owner', 'record'),
					_Utils_Tuple3('Subject', 'subject', 'text'),
					_Utils_Tuple3('Message', 'message', 'textarea')
				]);
		default:
			return _List_Nil;
	}
};
var $author$project$Features$heading = function (section) {
	switch (section) {
		case 'tasks':
			return _Utils_Tuple2('Edit and assign tasks', 'Select a task below to edit its deadline, owner and recurrence. A completed recurring task creates its next occurrence automatically.');
		case 'history':
			return _Utils_Tuple2('Client and case history', 'Keep conversations, decisions and next steps together. Notes are attributed to their author.');
		case 'documents':
			return _Utils_Tuple2('Document checklist and review', 'Create requirements, upload directly into an item, and record approval or feedback once scanning succeeds.');
		case 'reminders':
			return _Utils_Tuple2('Email reminders and escalation', 'Send deadline reminders to the assigned staff member and escalate overdue work to administrators.');
		case 'merge':
			return _Utils_Tuple2('Merge duplicate records', 'Preview both records before confirming. Children are preserved; the source is archived and its original fields remain available in the audit trail.');
		case 'reports':
			return _Utils_Tuple2('Management reports', 'Choose a date range. Lead conversions use the cohort created in that range; workload and overdue counts show the current position.');
		case 'search':
			return _Utils_Tuple2('Search and saved views', 'Search contacts, phone numbers, tasks and cases. Save personal views for work such as your overdue cases.');
		case 'security':
			return _Utils_Tuple2('Account security', 'Set up a SHA-256 compatible authenticator, keep recovery codes offline, and review or revoke active sessions.');
		case 'appointments':
			return _Utils_Tuple2('Appointments and calendar', 'Schedule appointments in UTC. Overlapping appointments for the same staff member are prevented.');
		case 'invoices':
			return _Utils_Tuple2('Invoices', 'Create drafts, issue invoices and record payment manually. Issued amounts are locked; no online payment is taken.');
		case 'portal':
			return _Utils_Tuple2('Client portal access', 'Create a private, one-use sign-in link. Only explicitly shared, approved files become downloadable by the client.');
		case 'notifications':
			return _Utils_Tuple2('Notification centre', 'Review assignments, deadlines, document rejections and overdue work. Preferences hide selected categories and control reminder emails.');
		case 'mail':
			return _Utils_Tuple2('Email delivery', 'Track queue status and failures. Accepted by SMTP means the mail server accepted the message; inbox delivery is not confirmed.');
		case 'ageing':
			return _Utils_Tuple2('Case ageing', 'Review open cases, their age and overdue deadlines. Exports contain up to 10,000 rows; narrow the date range for larger datasets.');
		case 'bottlenecks':
			return _Utils_Tuple2('Case bottlenecks', 'Cases grouped by stage, with time in the current stage. Legacy cases without stage history use their creation date.');
		case 'trends':
			return _Utils_Tuple2('Historical workload', 'Daily snapshots begin when the scheduler is enabled. Today updates during the day; previous days retain their last recorded workload.');
		case 'communication':
			return _Utils_Tuple2('Email a contact', 'Send through the configured mail service. Delivery is queued and the conversation is recorded in the shared history.');
		default:
			return _Utils_Tuple2('Workspace', '');
	}
};
var $author$project$Features$items = F2(
	function (key, item) {
		return A2(
			$elm$core$Result$withDefault,
			_List_Nil,
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2(
					$elm$json$Json$Decode$field,
					key,
					$elm$json$Json$Decode$list($elm$json$Json$Decode$value)),
				item));
	});
var $elm$html$Html$Attributes$placeholder = $elm$html$Html$Attributes$stringProperty('placeholder');
var $elm$core$Basics$round = _Basics_round;
var $author$project$Features$reportRow = function (item) {
	var n = function (key) {
		return A2(
			$elm$core$Result$withDefault,
			0,
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, key, $elm$json$Json$Decode$float),
				item));
	};
	var percentage = (!n('leads')) ? '0' : $elm$core$String$fromInt(
		$elm$core$Basics$round(
			(100 * n('converted')) / n('leads')));
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_Utils_ap(
			A2(
				$elm$core$List$map,
				function (_v0) {
					var key = _v0.a;
					var labelText = _v0.b;
					return A2(
						$elm$html$Html$p,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(labelText + ': ')
									])),
								$elm$html$Html$text(
								A2($author$project$Features$str, key, item))
							]));
				},
				_List_fromArray(
					[
						_Utils_Tuple2('leads', 'Leads in cohort'),
						_Utils_Tuple2('converted', 'Converted leads'),
						_Utils_Tuple2('openTasks', 'Open tasks'),
						_Utils_Tuple2('overdueTasks', 'Overdue tasks'),
						_Utils_Tuple2('completedCases', 'Cases completed'),
						_Utils_Tuple2('averageCaseDays', 'Average case days')
					])),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$p,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Conversion rate: ' + (percentage + '%'))
						]))
				])));
};
var $elm$html$Html$code = _VirtualDom_node('code');
var $author$project$Features$resultView = function (result) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('card'),
				A2($elm$html$Html$Attributes$attribute, 'role', 'status')
			]),
		_Utils_ap(
			_List_fromArray(
				[
					A2(
					$elm$html$Html$p,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($author$project$Features$str, 'message', result))
						]))
				]),
			_Utils_ap(
				A2(
					$elm$core$List$filterMap,
					function (key) {
						var value_ = A2($author$project$Features$str, key, result);
						return (value_ === '') ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
							A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$strong,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												(key === 'secret') ? 'Authenticator key: ' : ((key === 'uri') ? 'Authenticator setup URI: ' : 'Private client sign-in link: '))
											])),
										A2(
										$elm$html$Html$code,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(value_)
											]))
									])));
					},
					_List_fromArray(
						['secret', 'uri', 'url'])),
				_Utils_ap(
					$elm$core$List$isEmpty(
						A2($author$project$Features$items, 'counts', result)) ? _List_Nil : A2(
						$elm$core$List$map,
						function (counts) {
							return A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2(
											$elm$core$String$join,
											' · ',
											A2(
												$elm$core$List$map,
												function (key) {
													return key + (': ' + A2($author$project$Features$str, key, counts));
												},
												_List_fromArray(
													['documents', 'tasks', 'cases', 'notes', 'activities', 'invoices']))))
									]));
						},
						A2($author$project$Features$items, 'counts', result)),
					A2(
						$elm$core$List$map,
						function (value_) {
							return A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$code,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(value_)
											]))
									]));
						},
						A2(
							$elm$core$Result$withDefault,
							_List_Nil,
							A2(
								$elm$json$Json$Decode$decodeValue,
								A2(
									$elm$json$Json$Decode$field,
									'recoveryCodes',
									$elm$json$Json$Decode$list($elm$json$Json$Decode$string)),
								result)))))));
};
var $elm$html$Html$Attributes$rows = function (n) {
	return A2(
		_VirtualDom_attribute,
		'rows',
		$elm$core$String$fromInt(n));
};
var $author$project$Ui$spinner = A2(
	$elm$html$Html$div,
	_List_fromArray(
		[
			$elm$html$Html$Attributes$class('loading-state'),
			A2($elm$html$Html$Attributes$attribute, 'role', 'status'),
			A2($elm$html$Html$Attributes$attribute, 'aria-live', 'polite')
		]),
	_List_fromArray(
		[
			A2(
			$elm$html$Html$span,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('spinner'),
					A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true')
				]),
			_List_Nil),
			A2(
			$elm$html$Html$span,
			_List_Nil,
			_List_fromArray(
				[
					$elm$html$Html$text('Loading your workspace…')
				]))
		]));
var $elm$html$Html$textarea = _VirtualDom_node('textarea');
var $author$project$Features$view = F2(
	function (model, section) {
		var options = A2($author$project$Features$items, 'options', model.aM);
		var isViewer = _Utils_eq(
			A2(
				$elm$core$Maybe$map,
				function ($) {
					return $.aX;
				},
				model.a$),
			$elm$core$Maybe$Just('viewer'));
		var get = function (key) {
			return A2(
				$elm$core$Maybe$withDefault,
				'',
				A2($elm$core$Dict$get, key, model.cT));
		};
		var extraUsers = A2(
			$elm$core$Result$withDefault,
			_List_Nil,
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2(
					$elm$json$Json$Decode$at,
					_List_fromArray(
						['security', 'users']),
					$elm$json$Json$Decode$list($elm$json$Json$Decode$value)),
				model.aM));
		var control = function (_v6) {
			var labelText = _v6.a;
			var key = _v6.b;
			var kind = _v6.c;
			var selectedValue = get(key);
			var choices = A2($elm$core$String$contains, '|', kind) ? A2(
				$elm$core$List$map,
				function (v) {
					return _Utils_Tuple2(
						v,
						(v === 'true') ? 'Yes' : ((v === 'false') ? 'No' : v));
				},
				A2($elm$core$String$split, '|', kind)) : A2(
				$elm$core$List$map,
				function (item) {
					var v = A2($author$project$Features$str, 'value', item);
					return _Utils_Tuple2(
						A2(
							$elm$core$List$member,
							key,
							_List_fromArray(
								['assignee', 'task', 'source', 'target'])) ? A2(
							$elm$core$Maybe$withDefault,
							v,
							$elm$core$List$head(
								$elm$core$List$reverse(
									A2($elm$core$String$split, ':', v)))) : v,
						A2($author$project$Features$str, 'label', item));
				},
				A2(
					$elm$core$List$filter,
					function (item) {
						var v = A2($author$project$Features$str, 'value', item);
						switch (kind) {
							case 'record':
								return A2(
									$elm$core$List$any,
									function (prefix) {
										return A2($elm$core$String$startsWith, prefix, v);
									},
									_List_fromArray(
										['lead:', 'client:', 'case:']));
							case 'merge':
								return A2(
									$elm$core$String$startsWith,
									(get('entity') === 'clients') ? 'client:' : 'lead:',
									v);
							default:
								return A2($elm$core$String$startsWith, kind + ':', v);
						}
					},
					options));
			var attrs = _List_fromArray(
				[
					$elm$html$Html$Attributes$class('input'),
					$elm$html$Html$Attributes$value(selectedValue),
					$elm$html$Html$Events$onInput(
					$author$project$State$FeatureField(key)),
					$elm$html$Html$Attributes$id('work-' + key),
					A2($elm$html$Html$Attributes$attribute, 'aria-describedby', 'feature-error')
				]);
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('form-group')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$label,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$for('work-' + key)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(labelText)
							])),
						(kind === 'textarea') ? A2(
						$elm$html$Html$textarea,
						_Utils_ap(
							attrs,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$rows(4)
								])),
						_List_Nil) : ((A2(
						$elm$core$List$member,
						kind,
						_List_fromArray(
							['record', 'staff', 'task', 'client', 'document', 'merge'])) || A2($elm$core$String$contains, '|', kind)) ? A2(
						$elm$html$Html$select,
						attrs,
						A2(
							$elm$core$List$cons,
							A2(
								$elm$html$Html$option,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$value('')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Choose…')
									])),
							A2(
								$elm$core$List$map,
								function (_v4) {
									var v = _v4.a;
									var l = _v4.b;
									return A2(
										$elm$html$Html$option,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$value(v),
												$elm$html$Html$Attributes$selected(
												_Utils_eq(v, selectedValue))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(l)
											]));
								},
								choices))) : A2(
						$elm$html$Html$input,
						_Utils_ap(
							attrs,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$type_(kind)
								])),
						_List_Nil))
					]));
		};
		var canWrite = (!isViewer) || A2(
			$elm$core$List$member,
			section,
			_List_fromArray(
				['security', 'search', 'notifications']));
		var row = function (item) {
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('operation-row')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$h3,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2($author$project$Features$str, 'title', item))
									])),
								(section === 'reports') ? $author$project$Features$reportRow(item) : A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2(
											$elm$core$String$join,
											' · ',
											A2(
												$elm$core$List$filter,
												$elm$core$Basics$neq(''),
												A2(
													$elm$core$List$map,
													function (key) {
														var v = A2($author$project$Features$str, key, item);
														return (v === '') ? '' : ($author$project$Features$fieldLabel(key) + (': ' + v));
													},
													$author$project$Features$columns(section)))))
									])),
								(A2($author$project$Features$str, 'path', item) !== '') ? A2(
								$elm$html$Html$a,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Attributes$href(
										A2($author$project$Features$str, 'path', item))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Open record')
									])) : $elm$html$Html$text(''),
								A2(
								$elm$html$Html$div,
								_List_Nil,
								A2(
									$elm$core$List$map,
									function (file) {
										return (A2($author$project$Features$str, 'scanStatus', file) === 'Clean') ? A2(
											$elm$html$Html$a,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('btn btn-outline'),
													$elm$html$Html$Attributes$href(
													'/api/documents/' + (A2($author$project$Features$str, 'documentId', file) + '/download'))
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(
													'Version ' + (A2($author$project$Features$str, 'version', file) + (' · ' + A2($author$project$Features$str, 'filename', file))))
												])) : A2(
											$elm$html$Html$p,
											_List_Nil,
											_List_fromArray(
												[
													$elm$html$Html$text(
													'Version ' + (A2($author$project$Features$str, 'version', file) + (' · ' + (A2($author$project$Features$str, 'filename', file) + (' · ' + A2($author$project$Features$str, 'scanStatus', file))))))
												]));
									},
									A2($author$project$Features$items, 'versions', item))),
								(section === 'documents') ? A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Attributes$disabled(
										(!canWrite) || (model.aq || _Utils_eq(model.cB, $elm$core$Maybe$Nothing))),
										$elm$html$Html$Events$onClick(
										A2(
											$author$project$State$ChecklistUpload,
											A2(
												$elm$core$Maybe$withDefault,
												0,
												$elm$core$String$toInt(
													A2($author$project$Features$str, 'id', item))),
											A2(
												$elm$core$Maybe$withDefault,
												0,
												$elm$core$String$toInt(
													A2($author$project$Features$str, 'revision', item)))))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Upload selected file to this requirement')
									])) : $elm$html$Html$text('')
							])),
						A2(
						$elm$core$List$member,
						section,
						_List_fromArray(
							['history', 'reports', 'communication', 'ageing', 'bottlenecks', 'trends'])) ? $elm$html$Html$text('') : A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn btn-outline'),
								$elm$html$Html$Attributes$disabled(model.aq),
								$elm$html$Html$Events$onClick(
								$author$project$State$FeatureEdit(item))
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								(section === 'search') ? 'Select view' : 'Select / edit')
							]))
					]));
		};
		var action = F2(
			function (name, labelText) {
				return A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-primary'),
							$elm$html$Html$Attributes$disabled((!canWrite) || model.aq),
							$elm$html$Html$Events$onClick(
							A2(
								$elm$core$List$member,
								name,
								_List_fromArray(
									['confirm', 'suspend', 'revoke-user', 'grant', 'revoke', 'retry'])) ? A2(
								$author$project$State$ConfirmRequested,
								'Confirm: ' + (labelText + '?'),
								$author$project$State$FeatureRun(name)) : $author$project$State$FeatureRun(name))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(labelText)
						]));
			});
		var actions = function () {
			switch (section) {
				case 'tasks':
					return _Utils_ap(
						(model.Z !== '') ? _List_fromArray(
							[
								A2(action, 'create', 'Create task here')
							]) : _List_Nil,
						_List_fromArray(
							[
								A2(action, 'save', 'Save selected task')
							]));
				case 'history':
					return _List_fromArray(
						[
							A2(action, 'add', 'Add note')
						]);
				case 'merge':
					return _List_fromArray(
						[
							A2(action, 'preview', 'Preview merge'),
							A2(action, 'confirm', 'Confirm merge')
						]);
				case 'reports':
					return _List_fromArray(
						[
							A2(action, 'range', 'Update report')
						]);
				case 'ageing':
					return _List_fromArray(
						[
							A2(action, 'range', 'Update report')
						]);
				case 'bottlenecks':
					return _List_fromArray(
						[
							A2(action, 'range', 'Update report')
						]);
				case 'trends':
					return _List_fromArray(
						[
							A2(action, 'range', 'Update report')
						]);
				case 'mail':
					return _Utils_eq(
						A2(
							$elm$core$Maybe$map,
							function ($) {
								return $.aX;
							},
							model.a$),
						$elm$core$Maybe$Just('admin')) ? _List_fromArray(
						[
							A2(action, 'retry', 'Retry selected failed message')
						]) : _List_Nil;
				case 'notifications':
					return _List_fromArray(
						[
							A2(action, 'preferences', 'Save notification preferences'),
							A2(action, 'read', 'Mark selected notification read')
						]);
				case 'search':
					return _List_fromArray(
						[
							A2(action, 'save', 'Save personal view'),
							A2(action, 'views', 'Show saved views'),
							A2(action, 'apply', 'Open selected view'),
							A2(action, 'delete', 'Delete selected view')
						]);
				case 'security':
					return _List_fromArray(
						[
							A2(action, 'setup', 'Start authenticator setup'),
							A2(action, 'enable', 'Enable MFA'),
							A2(action, 'disable', 'Disable MFA'),
							A2(action, 'revoke', 'Revoke selected session')
						]);
				case 'documents':
					return _Utils_ap(
						_List_fromArray(
							[
								A2(action, 'save', 'Save checklist item')
							]),
						_Utils_ap(
							(model.Z === '') ? _List_fromArray(
								[
									A2(action, 'attach', 'Attach selected file as a new version')
								]) : _List_Nil,
							_Utils_eq(
								A2(
									$elm$core$Maybe$map,
									function ($) {
										return $.aX;
									},
									model.a$),
								$elm$core$Maybe$Just('admin')) ? _List_fromArray(
								[
									A2(action, 'rescan', 'Retry failed scan for selected item')
								]) : _List_Nil));
				case 'portal':
					return _List_fromArray(
						[
							A2(action, 'create', 'Create private sign-in link'),
							A2(action, 'grant', 'Share selected approved file'),
							A2(action, 'revoke', 'Revoke selected link')
						]);
				case 'communication':
					return _List_fromArray(
						[
							A2(action, 'send', 'Queue email')
						]);
				case 'invoices':
					return _List_fromArray(
						[
							A2(action, 'save', 'Save invoice'),
							A2(action, 'send', 'Email selected invoice')
						]);
				default:
					return _List_fromArray(
						[
							A2(action, 'save', 'Save changes')
						]);
			}
		}();
		var _v0 = $author$project$Features$heading(section);
		var title = _v0.a;
		var description = _v0.b;
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('page-head')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h2,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(title)
										])),
									A2(
									$elm$html$Html$p,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('page-description')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(description)
										]))
								]))
						])),
					(section === 'appointments') ? A2(
					$elm$html$Html$a,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-outline'),
							$elm$html$Html$Attributes$href('/api/workspace/calendar.ics')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Download calendar (.ics)')
						])) : $elm$html$Html$text(''),
					(section === 'security') ? A2(
					$elm$html$Html$p,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							_Utils_eq(
								A2(
									$elm$json$Json$Decode$decodeValue,
									A2(
										$elm$json$Json$Decode$at,
										_List_fromArray(
											['security', 'enabled']),
										$elm$json$Json$Decode$bool),
									model.aM),
								$elm$core$Result$Ok(true)) ? 'Authenticator protection is enabled.' : 'Authenticator protection is not enabled. Administrators may be required to set it up before opening records.')
						])) : $elm$html$Html$text(''),
					(!A2(
					$elm$core$List$member,
					section,
					_List_fromArray(
						['security', 'reports']))) ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-group')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$label,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$for('feature-search')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Search this list and record choices')
								])),
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$id('feature-search'),
									$elm$html$Html$Attributes$class('input'),
									$elm$html$Html$Attributes$value(model.a7),
									$elm$html$Html$Events$onInput($author$project$State$FeatureSearch),
									$elm$html$Html$Attributes$placeholder('Name, phone, task, case or file…')
								]),
							_List_Nil)
						])) : $elm$html$Html$text(''),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('card')
						]),
					_Utils_ap(
						A2(
							$elm$core$List$map,
							control,
							A2(
								$elm$core$List$filter,
								function (_v1) {
									var key = _v1.b;
									return (model.Z === '') || (key !== 'document');
								},
								$author$project$Features$fields(section))),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('form-actions')
									]),
								_Utils_ap(
									actions,
									_List_fromArray(
										[
											A2(
											$elm$html$Html$button,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('btn btn-outline'),
													$elm$html$Html$Events$onClick($author$project$State$FeatureReset)
												]),
											_List_fromArray(
												[
													$elm$html$Html$text('New / clear form')
												]))
										])))
							]))),
					(model.bH !== '') ? A2(
					$elm$html$Html$p,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$id('feature-error'),
							$elm$html$Html$Attributes$class('error-banner'),
							A2($elm$html$Html$Attributes$attribute, 'role', 'alert')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(model.bH)
						])) : A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$id('feature-error')
						]),
					_List_Nil),
					(section === 'documents') ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('card')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$label,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$for('checklist-file')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Upload directly into a checklist item (up to 25 MB)')
								])),
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$id('checklist-file'),
									$elm$html$Html$Attributes$type_('file'),
									A2(
									$elm$html$Html$Events$on,
									'change',
									A2(
										$elm$json$Json$Decode$map,
										$author$project$State$ChecklistFile,
										A2(
											$elm$json$Json$Decode$at,
											_List_fromArray(
												['target', 'files']),
											A2($elm$json$Json$Decode$index, 0, $elm$file$File$decoder))))
								]),
							_List_Nil),
							A2(
							$elm$html$Html$p,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Choose a file, then use the upload button on its requirement. Files remain quarantined until scanning succeeds.')
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('form-actions')
								]),
							A2(
								$elm$core$List$map,
								function (_v2) {
									var filter = _v2.a;
									var labelText = _v2.b;
									return A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('btn btn-outline'),
												$elm$html$Html$Events$onClick(
												$author$project$State$FeatureSearch(filter))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(labelText)
											]));
								},
								_List_fromArray(
									[
										_Utils_Tuple2('review', 'Review queue'),
										_Utils_Tuple2('expiring', 'Expiring documents'),
										_Utils_Tuple2('outstanding', 'Outstanding requirements'),
										_Utils_Tuple2('', 'All documents')
									]))),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Attributes$disabled(model.aq),
									$elm$html$Html$Events$onClick(
									$author$project$State$PageStep(0))
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Refresh scan status')
								]))
						])) : $elm$html$Html$text(''),
					(section === 'reports') ? A2(
					$elm$html$Html$a,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-outline'),
							$elm$html$Html$Attributes$href('/api/workspace/reports.csv?q=' + model.a7)
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Export summary CSV')
						])) : $elm$html$Html$text(''),
					(section === 'documents') ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('summary-strip')
						]),
					A2(
						$elm$core$List$map,
						function (summary) {
							return A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										'Required: ' + (A2($author$project$Features$str, 'required', summary) + (' · Outstanding: ' + (A2($author$project$Features$str, 'outstanding', summary) + (' · Awaiting review: ' + (A2($author$project$Features$str, 'review', summary) + (' · Expiring: ' + A2($author$project$Features$str, 'expiring', summary))))))))
									]));
						},
						A2($author$project$Features$items, 'summary', model.aM))) : $elm$html$Html$text(''),
					A2(
					$elm$core$List$member,
					section,
					_List_fromArray(
						['ageing', 'bottlenecks', 'trends'])) ? A2(
					$elm$html$Html$a,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-outline'),
							$elm$html$Html$Attributes$href('/api/workspace/report-export/' + (section + ('?q=' + model.a7)))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Export CSV')
						])) : $elm$html$Html$text(''),
					$author$project$Features$resultView(model.a6),
					model.c7 ? $author$project$Ui$spinner : A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('operations-list')
						]),
					A2($elm$core$List$map, row, model.bY)),
					(section === 'search') ? A2(
					$elm$html$Html$div,
					_List_Nil,
					A2(
						$elm$core$List$map,
						row,
						A2(
							$elm$core$Result$withDefault,
							_List_Nil,
							A2(
								$elm$json$Json$Decode$decodeValue,
								$elm$json$Json$Decode$list($elm$json$Json$Decode$value),
								model.a6)))) : $elm$html$Html$text(''),
					A2(
					$elm$html$Html$div,
					_List_Nil,
					A2(
						$elm$core$List$map,
						row,
						A2($author$project$Features$items, 'results', model.a6))),
					(section === 'security') ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('card')
						]),
					A2(
						$elm$core$List$cons,
						A2(
							$elm$html$Html$h3,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Team access')
								])),
						_Utils_ap(
							A2(
								$elm$core$List$map,
								function (item) {
									return A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('operation-row')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$span,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text(
														A2($author$project$Features$str, 'name', item) + (' · ' + (A2($author$project$Features$str, 'role', item) + ((A2($author$project$Features$str, 'suspended', item) === '1') ? ' · Suspended' : ' · Active'))))
													])),
												A2(
												$elm$html$Html$button,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('btn btn-outline'),
														$elm$html$Html$Attributes$disabled(model.aq),
														$elm$html$Html$Events$onClick(
														$author$project$State$FeatureEdit(item))
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Select account')
													]))
											]));
								},
								extraUsers),
							_Utils_eq(
								A2(
									$elm$core$Maybe$map,
									function ($) {
										return $.aX;
									},
									model.a$),
								$elm$core$Maybe$Just('admin')) ? _List_fromArray(
								[
									A2(action, 'suspend', 'Suspend selected account'),
									A2(action, 'resume', 'Resume selected account'),
									A2(action, 'revoke-user', 'Revoke selected account sessions')
								]) : _List_Nil))) : $elm$html$Html$text('')
				]));
	});
var $author$project$Features$embedded = F2(
	function (model, cid) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('inline-workspace'),
					A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Client and case work')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$h2,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Work on this client or case')
						])),
					A2(
					$elm$html$Html$label,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$for('case-work-scope')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Scope')
						])),
					A2(
					$elm$html$Html$select,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$id('case-work-scope'),
							$elm$html$Html$Attributes$class('input'),
							$elm$html$Html$Attributes$value(model.Z),
							$elm$html$Html$Events$onInput($author$project$State$InlineOwner)
						]),
					A2(
						$elm$core$List$cons,
						A2(
							$elm$html$Html$option,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$value(
									'client:' + $elm$core$String$fromInt(cid)),
									$elm$html$Html$Attributes$selected(
									_Utils_eq(
										model.Z,
										'client:' + $elm$core$String$fromInt(cid)))
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Whole client')
								])),
						A2(
							$elm$core$List$map,
							function (c) {
								return A2(
									$elm$html$Html$option,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$value(
											'case:' + $elm$core$String$fromInt(c.a9)),
											$elm$html$Html$Attributes$selected(
											_Utils_eq(
												model.Z,
												'case:' + $elm$core$String$fromInt(c.a9)))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											A2($elm$core$Maybe$withDefault, 'Case', c.cy) + (' · ' + (c.$7 + (' · ' + $elm$core$String$fromInt(c.a9)))))
										]));
							},
							A2(
								$elm$core$Maybe$withDefault,
								_List_Nil,
								A2(
									$elm$core$Maybe$map,
									function ($) {
										return $.cx;
									},
									model.cC))))),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-actions'),
							A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Client work sections')
						]),
					A2(
						$elm$core$List$map,
						function (_v0) {
							var section = _v0.a;
							var labelText = _v0.b;
							return A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class(
										_Utils_eq(model.bb, section) ? 'btn btn-primary' : 'btn btn-outline'),
										A2(
										$elm$html$Html$Attributes$attribute,
										'aria-pressed',
										_Utils_eq(model.bb, section) ? 'true' : 'false'),
										$elm$html$Html$Events$onClick(
										$author$project$State$InlineSection(section))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(labelText)
									]));
						},
						_List_fromArray(
							[
								_Utils_Tuple2('tasks', 'Edit tasks'),
								_Utils_Tuple2('history', 'Conversation history'),
								_Utils_Tuple2('documents', 'Document checklist')
							]))),
					A2($author$project$Features$view, model, model.bb),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-actions')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Attributes$disabled(!model.c8),
									$elm$html$Html$Events$onClick(
									$author$project$State$PageStep(-1))
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Previous work page')
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Attributes$disabled(
									$elm$core$List$length(model.bY) < 50),
									$elm$html$Html$Events$onClick(
									$author$project$State$PageStep(1))
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Next work page')
								]))
						]))
				]));
	});
var $author$project$Ui$fmtDate = function (md) {
	return A2(
		$elm$core$Maybe$withDefault,
		'—',
		A2(
			$elm$core$Maybe$map,
			$elm$core$String$left(10),
			md));
};
var $author$project$State$UpdateAddTask = function (a) {
	return {$: 94, a: a};
};
var $author$project$Views$plainOptions = $elm$core$List$map(
	function (s) {
		return _Utils_Tuple2(s, s);
	});
var $author$project$Types$priorities = _List_fromArray(
	['Low', 'Medium', 'High']);
var $author$project$Views$selectFieldMsg = F4(
	function (lbl, opts, current, onChange) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('filter-group')
				]),
			_List_fromArray(
				[
					(lbl === '') ? A2($elm$html$Html$span, _List_Nil, _List_Nil) : A2(
					$elm$html$Html$label,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(lbl)
						])),
					A2(
					$elm$html$Html$select,
					_List_fromArray(
						[
							$elm$html$Html$Events$onInput(onChange)
						]),
					A2(
						$elm$core$List$map,
						function (_v0) {
							var v = _v0.a;
							var optLbl = _v0.b;
							return A2(
								$elm$html$Html$option,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$value(v),
										$elm$html$Html$Attributes$selected(
										_Utils_eq(v, current))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(optLbl)
									]));
						},
						opts))
				]));
	});
var $author$project$Views$taskComposer = F2(
	function (model, submitMsg) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('inline-form'),
					A2($elm$html$Html$Attributes$style, 'margin-bottom', '10px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-group'),
							A2($elm$html$Html$Attributes$style, 'flex', '2')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('input'),
									$elm$html$Html$Attributes$placeholder('New task title…'),
									$elm$html$Html$Attributes$value(model.k.ay),
									$elm$html$Html$Events$onInput(
									function (v) {
										return $author$project$State$UpdateAddTask(
											function (f) {
												return _Utils_update(
													f,
													{ay: v});
											});
									})
								]),
							_List_Nil)
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-group')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$type_('date'),
									$elm$html$Html$Attributes$class('input'),
									$elm$html$Html$Attributes$value(model.k.aK),
									$elm$html$Html$Events$onInput(
									function (v) {
										return $author$project$State$UpdateAddTask(
											function (f) {
												return _Utils_update(
													f,
													{aK: v});
											});
									})
								]),
							_List_Nil)
						])),
					A4(
					$author$project$Views$selectFieldMsg,
					'',
					$author$project$Views$plainOptions($author$project$Types$priorities),
					model.k.bl,
					function (v) {
						return $author$project$State$UpdateAddTask(
							function (f) {
								return _Utils_update(
									f,
									{bl: v});
							});
					}),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$disabled(
							$author$project$Views$isReadOnly(model)),
							$elm$html$Html$Attributes$class('btn btn-sm btn-primary'),
							$elm$html$Html$Events$onClick(submitMsg)
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Add Task')
						]))
				]));
	});
var $author$project$State$TaskDeleted = function (a) {
	return {$: 91, a: a};
};
var $author$project$State$TaskStatusPicked = F2(
	function (a, b) {
		return {$: 89, a: a, b: b};
	});
var $author$project$Ui$priorityBadge = function (priority) {
	return A2(
		$elm$html$Html$span,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class(
				'task-priority-badge ' + $elm$core$String$toLower(priority))
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(priority)
			]));
};
var $author$project$Types$taskStatuses = _List_fromArray(
	['Pending', 'In Progress', 'Done']);
var $author$project$Views$taskRows = F2(
	function (model, tasks) {
		return $elm$core$List$isEmpty(tasks) ? $author$project$Ui$emptyNote('No tasks yet.') : A2(
			$elm$html$Html$div,
			_List_Nil,
			A2(
				$elm$core$List$map,
				function (t) {
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('task-row')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$select,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$disabled(
										$author$project$Views$isReadOnly(model)),
										A2($elm$html$Html$Attributes$style, 'padding', '4px'),
										A2($elm$html$Html$Attributes$style, 'border-radius', '6px'),
										A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Status for ' + t.ay),
										$elm$html$Html$Events$onInput(
										$author$project$State$TaskStatusPicked(t.a9))
									]),
								A2(
									$elm$core$List$map,
									function (s) {
										return A2(
											$elm$html$Html$option,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$value(s),
													$elm$html$Html$Attributes$selected(
													_Utils_eq(s, t.dr))
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(s)
												]));
									},
									$author$project$Types$taskStatuses)),
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class(
										(t.dr === 'Done') ? 'done-title' : '')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(t.ay)
									])),
								$author$project$Ui$priorityBadge(t.bl),
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('activity-date')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										$author$project$Ui$fmtDate(t.aK))
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$disabled(
										$author$project$Views$isReadOnly(model)),
										$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
										$elm$html$Html$Events$onClick(
										A2(
											$author$project$State$ConfirmRequested,
											'Delete this task? This action cannot be undone.',
											$author$project$State$TaskDeleted(t.a9)))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('✕')
									]))
							]));
				},
				tasks));
	});
var $author$project$Views$clientDetailView = F2(
	function (model, cid) {
		var _v0 = model.cC;
		if (_v0.$ === 1) {
			return $author$project$Ui$spinner;
		} else {
			var cd = _v0.a;
			var caseRow = function (cr) {
				return A2(
					$elm$html$Html$tr,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$html$Html$td,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									A2($elm$core$Maybe$withDefault, '—', cr.cy))
								])),
							A2(
							$elm$html$Html$td,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									A2($elm$core$Maybe$withDefault, '—', cr.aJ))
								])),
							A2(
							$elm$html$Html$td,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('tag tag-stage-blue')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(cr.$7)
										]))
								])),
							A2(
							$elm$html$Html$td,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									$author$project$Ui$fmtDate(cr.aI))
								])),
							A2(
							$elm$html$Html$td,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$disabled(
											$author$project$Views$isReadOnly(model)),
											$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
											$elm$html$Html$Events$onClick(
											$author$project$State$OpenCaseForm(
												$elm$core$Maybe$Just(cr)))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Edit')
										]))
								])),
							A2(
							$elm$html$Html$td,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$disabled(
											$author$project$Views$isReadOnly(model)),
											$elm$html$Html$Attributes$class('btn btn-sm btn-danger'),
											$elm$html$Html$Events$onClick(
											A2(
												$author$project$State$ConfirmRequested,
												'Delete this case? This action cannot be undone.',
												$author$project$State$DeleteCaseClicked(cr.a9)))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Delete')
										]))
								]))
						]));
			};
			var c = cd.a0;
			return A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$a,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('back-link'),
								$elm$html$Html$Attributes$href('#'),
								$elm$html$Html$Events$onClick(
								$author$project$State$NavigateTo('/clients'))
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('← Back to Clients')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('page-head')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h2,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(c.bK)
											])),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('lead-detail-badges')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$span,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('tag tag-id')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(c.bV)
													]))
											]))
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('flex')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn'),
												$elm$html$Html$Events$onClick(
												$author$project$State$OpenCaseForm($elm$core$Maybe$Nothing))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('+ Add Case')
											])),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn'),
												$elm$html$Html$Events$onClick(
												$author$project$State$OpenClientEditor(c.a9))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Edit')
											])),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn btn-danger'),
												$elm$html$Html$Events$onClick(
												A2(
													$author$project$State$ConfirmRequested,
													'Move this client to the archive? Its cases, documents and history will be preserved.',
													$author$project$State$DeleteClientConfirmed(c.a9)))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Delete')
											]))
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('detail-grid')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('card')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('section-head')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$h3,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Details')
													]))
											])),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('kv-grid')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$div,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('kv')
													]),
												_List_fromArray(
													[
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text('Email')
															])),
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text(
																A2($elm$core$Maybe$withDefault, '—', c.ap))
															]))
													])),
												A2(
												$elm$html$Html$div,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('kv')
													]),
												_List_fromArray(
													[
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text('Phone')
															])),
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text(
																A2($elm$core$Maybe$withDefault, '—', c.bZ))
															]))
													])),
												A2(
												$elm$html$Html$div,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('kv')
													]),
												_List_fromArray(
													[
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text('Case Officer')
															])),
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text(
																A2($elm$core$Maybe$withDefault, '—', c.cw))
															]))
													])),
												A2(
												$elm$html$Html$div,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('kv')
													]),
												_List_fromArray(
													[
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text('Since')
															])),
														A2(
														$elm$html$Html$div,
														_List_Nil,
														_List_fromArray(
															[
																$elm$html$Html$text(
																$author$project$Ui$fmtDateTime(c.W))
															]))
													]))
											]))
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('card table-card')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('section-head')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$h3,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Cases')
													]))
											])),
										$elm$core$List$isEmpty(cd.cx) ? $author$project$Ui$emptyNote('No cases yet — add one.') : A2(
										$elm$html$Html$table,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('data-table')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$thead,
												_List_Nil,
												_List_fromArray(
													[
														A2(
														$elm$html$Html$tr,
														_List_Nil,
														_List_fromArray(
															[
																A2(
																$elm$html$Html$th,
																_List_Nil,
																_List_fromArray(
																	[
																		$elm$html$Html$text('Service')
																	])),
																A2(
																$elm$html$Html$th,
																_List_Nil,
																_List_fromArray(
																	[
																		$elm$html$Html$text('Destination')
																	])),
																A2(
																$elm$html$Html$th,
																_List_Nil,
																_List_fromArray(
																	[
																		$elm$html$Html$text('Stage')
																	])),
																A2(
																$elm$html$Html$th,
																_List_Nil,
																_List_fromArray(
																	[
																		$elm$html$Html$text('Deadline')
																	])),
																A2($elm$html$Html$th, _List_Nil, _List_Nil),
																A2($elm$html$Html$th, _List_Nil, _List_Nil)
															]))
													])),
												A2(
												$elm$html$Html$tbody,
												_List_Nil,
												A2($elm$core$List$map, caseRow, cd.cx))
											]))
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('detail-grid'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
							]),
						_List_fromArray(
							[
								A3(
								$author$project$Views$documentsCard,
								model,
								cd.bC,
								$author$project$State$UploadClientDocClicked(cd.a0.a9)),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('card')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('section-head')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$h3,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Tasks & follow-ups')
													])),
												A2(
												$elm$html$Html$button,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
														$elm$html$Html$Events$onClick(
														$author$project$State$NavigateTo('/tasks'))
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Manage tasks ↗')
													]))
											])),
										A2(
										$author$project$Views$taskComposer,
										model,
										$author$project$State$SubmitClientTask(cd.a0.a9)),
										A2($author$project$Views$taskRows, model, cd.J)
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('card')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h3,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text('Journey history')
											])),
										$elm$core$List$isEmpty(cd.bu) ? $author$project$Ui$emptyNote('Activity will appear here as the relationship grows.') : A2(
										$elm$html$Html$div,
										_List_Nil,
										A2(
											$elm$core$List$map,
											function (activity) {
												return A2(
													$elm$html$Html$div,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$class('activity-item')
														]),
													_List_fromArray(
														[
															A2(
															$elm$html$Html$span,
															_List_fromArray(
																[
																	$elm$html$Html$Attributes$class('activity-date')
																]),
															_List_fromArray(
																[
																	$elm$html$Html$text(activity.cI)
																])),
															$elm$html$Html$text(
															A2($elm$core$Maybe$withDefault, '', activity.a4))
														]));
											},
											cd.bu))
									]))
							])),
						A2($author$project$Features$embedded, model, cid),
						function () {
						var _v1 = model.w;
						if (!_v1.$) {
							var cf = _v1.a;
							return A3($author$project$Views$caseModal, model, cf, cd);
						} else {
							return A2($elm$html$Html$div, _List_Nil, _List_Nil);
						}
					}()
					]));
		}
	});
var $author$project$State$ClientSearchChanged = function (a) {
	return {$: 99, a: a};
};
var $author$project$State$OpenAddClient = {$: 100};
var $author$project$State$CloseClientForm = {$: 101};
var $author$project$State$SubmitClientForm = {$: 103};
var $author$project$State$UpdateClientForm = function (a) {
	return {$: 102, a: a};
};
var $author$project$Views$clientFormModal = function (model) {
	var title = function () {
		var _v0 = model.aF;
		if (!_v0.$) {
			return 'Edit Client';
		} else {
			return 'Add Client';
		}
	}();
	var f = model.n;
	return A2(
		$author$project$Ui$modal,
		title,
		A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A4(
					$author$project$Ui$inputField,
					'Full Name *',
					f.bK,
					'text',
					function (v) {
						return $author$project$State$UpdateClientForm(
							function (g) {
								return _Utils_update(
									g,
									{bK: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Email',
					f.ap,
					'email',
					function (v) {
						return $author$project$State$UpdateClientForm(
							function (g) {
								return _Utils_update(
									g,
									{ap: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Phone',
					f.bZ,
					'text',
					function (v) {
						return $author$project$State$UpdateClientForm(
							function (g) {
								return _Utils_update(
									g,
									{bZ: v});
							});
					}),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-group')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$label,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Case Officer')
								])),
							A2(
							$elm$html$Html$select,
							_List_fromArray(
								[
									$elm$html$Html$Events$onInput(
									function (v) {
										return $author$project$State$UpdateClientForm(
											function (g) {
												return _Utils_update(
													g,
													{bX: v});
											});
									})
								]),
							A2(
								$elm$core$List$cons,
								A2(
									$elm$html$Html$option,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$value('')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('— none —')
										])),
								A2(
									$elm$core$List$map,
									function (u) {
										return A2(
											$elm$html$Html$option,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$value(
													$elm$core$String$fromInt(u.a9)),
													$elm$html$Html$Attributes$selected(
													_Utils_eq(
														A2(
															$elm$core$Maybe$withDefault,
															'',
															A2(
																$elm$core$Maybe$map,
																$elm$core$String$fromInt,
																$elm$core$Maybe$Just(u.a9))),
														f.bX))
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(u.t)
												]));
									},
									model.T)))
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('flex'),
							A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$disabled(
									$author$project$Views$isReadOnly(model)),
									$elm$html$Html$Attributes$class('btn btn-primary'),
									$elm$html$Html$Events$onClick($author$project$State$SubmitClientForm)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Save')
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Events$onClick($author$project$State$CloseClientForm)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Cancel')
								]))
						]))
				])));
};
var $author$project$Ui$emptyState = F3(
	function (symbol, title, description) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('empty-state')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('empty-state-icon')
						]),
					_List_fromArray(
						[
							$author$project$Ui$icon(symbol)
						])),
					A2(
					$elm$html$Html$h3,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(title)
						])),
					A2(
					$elm$html$Html$p,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(description)
						]))
				]));
	});
var $author$project$Api$exportCsvUrl = F2(
	function (ctx, kind) {
		return ctx.M + ('/api/export/' + (kind + '.csv'));
	});
var $author$project$Views$clientsView = function (model) {
	var row = function (c) {
		return A2(
			$elm$html$Html$tr,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$html$Html$a,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('contact-identity'),
									$elm$html$Html$Attributes$href(
									'/clients/' + $elm$core$String$fromInt(c.a9))
								]),
							_List_fromArray(
								[
									$author$project$Ui$avatar(c.bK),
									A2(
									$elm$html$Html$div,
									_List_Nil,
									_List_fromArray(
										[
											A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('lead-name')
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(c.bK)
												])),
											A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('lead-source')
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(
													A2($elm$core$Maybe$withDefault, 'No email added', c.ap))
												]))
										]))
								]))
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(c.bV)
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($elm$core$Maybe$withDefault, '—', c.bZ))
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($elm$core$Maybe$withDefault, '—', c.cw))
						])),
					A2(
					$elm$html$Html$td,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('lead-source')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							$author$project$Ui$fmtDateTime(c.W))
						]))
				]));
	};
	var q = $elm$core$String$toLower(
		$elm$core$String$trim(model.aG));
	var visible = A2(
		$elm$core$List$filter,
		function (c) {
			return (q === '') || (A2(
				$elm$core$String$contains,
				q,
				$elm$core$String$toLower(c.bK)) || A2(
				$elm$core$String$contains,
				q,
				$elm$core$String$toLower(c.bV)));
		},
		model.am);
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('page-head')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('Clients')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('flex')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$a,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Attributes$href(
										A2(
											$author$project$Api$exportCsvUrl,
											{M: model.ak, du: model.du},
											'clients')),
										$elm$html$Html$Attributes$download('')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Export CSV')
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$disabled(
										$author$project$Views$isReadOnly(model)),
										$elm$html$Html$Attributes$class('btn btn-primary'),
										$elm$html$Html$Events$onClick($author$project$State$OpenAddClient)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('+ Add Client')
									]))
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('search-container')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('search-row')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('search-input-wrapper')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$input,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('search-input'),
												A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Search clients'),
												$elm$html$Html$Attributes$placeholder('Search clients…'),
												$elm$html$Html$Attributes$value(model.aG),
												$elm$html$Html$Events$onInput($author$project$State$ClientSearchChanged)
											]),
										_List_Nil)
									]))
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('card table-card'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '12px')
					]),
				_List_fromArray(
					[
						$elm$core$List$isEmpty(visible) ? A3($author$project$Ui$emptyState, 'clients', 'No clients to show', 'Try another search, add a client, or convert a qualified lead.') : A2(
						$elm$html$Html$table,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('data-table clients-table')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$thead,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$tr,
										_List_Nil,
										_List_fromArray(
											[
												A2(
												$elm$html$Html$th,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Client')
													])),
												A2(
												$elm$html$Html$th,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Number')
													])),
												A2(
												$elm$html$Html$th,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Phone')
													])),
												A2(
												$elm$html$Html$th,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Case Officer')
													])),
												A2(
												$elm$html$Html$th,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Since')
													]))
											]))
									])),
								A2(
								$elm$html$Html$tbody,
								_List_Nil,
								A2($elm$core$List$map, row, visible))
							]))
					])),
				model.au ? $author$project$Views$clientFormModal(model) : A2($elm$html$Html$div, _List_Nil, _List_Nil)
			]));
};
var $author$project$Types$leadStages = _List_fromArray(
	['New Lead', 'Contacted', 'Initial Assessment', 'Qualified', 'Consultation Booked', 'Proposal Sent', 'Converted', 'Closed/Lost']);
var $elm$core$List$maximum = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(
			A3($elm$core$List$foldl, $elm$core$Basics$max, x, xs));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Views$statCard = F5(
	function (symbol, label, sub, value, path) {
		return A2(
			$elm$html$Html$a,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('stat stat-' + symbol),
					$elm$html$Html$Attributes$href(path)
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('stat-top')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('stat-label')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(label)
								])),
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('stat-icon')
								]),
							_List_fromArray(
								[
									$author$project$Ui$icon(symbol)
								]))
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('stat-value')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(value)
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('stat-sub')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(sub)
								])),
							$author$project$Ui$icon('arrow')
						]))
				]));
	});
var $elm$core$List$sum = function (numbers) {
	return A3($elm$core$List$foldl, $elm$core$Basics$add, 0, numbers);
};
var $author$project$Views$dashboardView = function (model) {
	var _v0 = model.dq;
	if (_v0.$ === 1) {
		return $author$project$Ui$spinner;
	} else {
		var stats = _v0.a;
		var totalSources = A2(
			$elm$core$Basics$max,
			1,
			$elm$core$List$sum(
				A2(
					$elm$core$List$map,
					function ($) {
						return $.aH;
					},
					stats.dn)));
		var taskRow = function (task) {
			return A2(
				$elm$html$Html$a,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('priority-task'),
						$elm$html$Html$Attributes$href(
						A2(
							$elm$core$Maybe$withDefault,
							'/leads/' + $elm$core$String$fromInt(task.aP),
							A2(
								$elm$core$Maybe$map,
								function (id) {
									return '/clients/' + $elm$core$String$fromInt(id);
								},
								task.a1)))
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('task-checkbox'),
								A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true')
							]),
						_List_Nil),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('priority-task-copy')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(task.ay)
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2($elm$core$Maybe$withDefault, 'Unlinked task', task.bS))
									]))
							])),
						$author$project$Ui$priorityBadge(task.bl),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class(
								(_Utils_cmp(
									A2($elm$core$Maybe$withDefault, '9999', task.aK),
									model.cf) < 0) ? 'due-label overdue' : 'due-label')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$author$project$Ui$fmtDate(task.aK))
							])),
						$author$project$Ui$icon('arrow')
					]));
		};
		var sourceRow = function (sc) {
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('source-row')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('source-symbol')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								A2($elm$core$String$left, 1, sc.ah))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('source-info')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(sc.ah)
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('source-track')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												A2(
												$elm$html$Html$Attributes$style,
												'width',
												$elm$core$String$fromInt(
													$elm$core$Basics$round((100 * sc.aH) / totalSources)) + '%')
											]),
										_List_Nil)
									]))
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('source-count')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$elm$core$String$fromInt(sc.aH))
							]))
					]));
		};
		var panelTitle = F3(
			function (title, subtitle, path) {
				return A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('panel-heading')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h3,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(title)
										])),
									A2(
									$elm$html$Html$p,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(subtitle)
										]))
								])),
							A2(
							$elm$html$Html$a,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('panel-link'),
									$elm$html$Html$Attributes$href(path)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('View all'),
									$author$project$Ui$icon('arrow')
								]))
						]));
			});
		var orderedStages = A2(
			$elm$core$List$concatMap,
			function (stageName) {
				return A2(
					$elm$core$List$filter,
					function (item) {
						return _Utils_eq(item.$7, stageName);
					},
					stats.dp);
			},
			$author$project$Types$leadStages);
		var maxStage = A2(
			$elm$core$Maybe$withDefault,
			1,
			$elm$core$List$maximum(
				A2(
					$elm$core$List$map,
					function ($) {
						return $.aH;
					},
					stats.dp)));
		var stageRow = function (sc) {
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('pipeline-row')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('pipeline-label')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(sc.$7)
									])),
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$String$fromInt(sc.aH))
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('stage-bar'),
								A2($elm$html$Html$Attributes$attribute, 'role', 'meter'),
								A2($elm$html$Html$Attributes$attribute, 'aria-label', sc.$7),
								A2(
								$elm$html$Html$Attributes$attribute,
								'aria-valuenow',
								$elm$core$String$fromInt(sc.aH)),
								A2($elm$html$Html$Attributes$attribute, 'aria-valuemin', '0'),
								A2(
								$elm$html$Html$Attributes$attribute,
								'aria-valuemax',
								$elm$core$String$fromInt(
									A2($elm$core$Basics$max, 1, maxStage)))
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('stage-fill'),
										A2(
										$elm$html$Html$Attributes$style,
										'width',
										$elm$core$String$fromInt(
											$elm$core$Basics$round(
												(100 * sc.aH) / A2($elm$core$Basics$max, 1, maxStage))) + '%')
									]),
								_List_Nil)
							]))
					]));
		};
		var activityRow = function (activity) {
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('feed-item')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('feed-dot'),
								A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true')
							]),
						_List_Nil),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('feed-copy')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('feed-meta')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$span,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												A3($elm$core$String$replace, '_', ' ', activity.c_))
											])),
										A2(
										$elm$html$Html$span,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												$author$project$Ui$fmtDate(
													$elm$core$Maybe$Just(activity.cI)))
											]))
									])),
								A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2($elm$core$Maybe$withDefault, 'Activity recorded', activity.a4))
									])),
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('text-muted')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2($elm$core$Maybe$withDefault, '', activity.bS))
									]))
							]))
					]));
		};
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('dashboard')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('stats dashboard-stats')
						]),
					_List_fromArray(
						[
							A5(
							$author$project$Views$statCard,
							'leads',
							'Active leads',
							$elm$core$String$fromInt(stats.cW) + ' high-priority relationships',
							$elm$core$String$fromInt(stats.dw),
							'/leads'),
							A5(
							$author$project$Views$statCard,
							'clients',
							'Clients',
							'People you’re helping move forward',
							$elm$core$String$fromInt(stats.dv),
							'/clients'),
							A5(
							$author$project$Views$statCard,
							'tasks',
							'Open tasks',
							'Your next steps, in one place',
							$elm$core$String$fromInt(stats.c5),
							'/tasks'),
							A5(
							$author$project$Views$statCard,
							'clock',
							'Overdue tasks',
							(!stats.c6) ? 'No overdue tasks' : 'A little attention goes a long way',
							$elm$core$String$fromInt(stats.c6),
							'/tasks')
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class(
							(stats.c6 > 0) ? 'attention-strip' : 'attention-strip on-track')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('attention-icon')
								]),
							_List_fromArray(
								[
									$author$project$Ui$icon(
									(stats.c6 > 0) ? 'clock' : 'check')
								])),
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$strong,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(
											(stats.c6 > 0) ? ($elm$core$String$fromInt(stats.c6) + ' tasks need your attention') : 'You’re on top of your tasks')
										])),
									A2(
									$elm$html$Html$p,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(
											(stats.c6 > 0) ? 'Start with overdue work, then make space for what’s next.' : 'Keep the momentum going. Review upcoming work and follow-ups.')
										]))
								])),
							A2(
							$elm$html$Html$a,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('attention-link'),
									$elm$html$Html$Attributes$href('/tasks')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Review tasks'),
									$author$project$Ui$icon('arrow')
								]))
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('dashboard-grid')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('card pipeline-panel')
								]),
							_List_fromArray(
								[
									A3(panelTitle, 'Your pipeline', 'Where every relationship stands', '/leads'),
									$elm$core$List$isEmpty(orderedStages) ? A3($author$project$Ui$emptyState, 'leads', 'Your pipeline starts here', 'Add your first lead to see your relationships take shape.') : A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('pipeline-list')
										]),
									A2($elm$core$List$map, stageRow, orderedStages))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('card sources-panel')
								]),
							_List_fromArray(
								[
									A3(panelTitle, 'Where leads find you', 'Your sources at a glance', '/leads'),
									$elm$core$List$isEmpty(stats.dn) ? A3($author$project$Ui$emptyState, 'clients', 'No sources yet', 'Sources appear when you start adding leads.') : A2(
									$elm$html$Html$div,
									_List_Nil,
									A2($elm$core$List$map, sourceRow, stats.dn))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('card priorities-panel')
								]),
							_List_fromArray(
								[
									A3(panelTitle, 'Next on your list', 'The next steps on your schedule', '/tasks'),
									$elm$core$List$isEmpty(stats.dx) ? A3($author$project$Ui$emptyState, 'check', 'A little breathing room', 'No upcoming tasks. Add a next step when you’re ready.') : A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('priority-list')
										]),
									A2($elm$core$List$map, taskRow, stats.dx))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('card activity-panel')
								]),
							_List_fromArray(
								[
									A3(panelTitle, 'Latest activity', 'The small steps that move things forward', '/leads'),
									$elm$core$List$isEmpty(stats.df) ? A3($author$project$Ui$emptyState, 'clock', 'Your story starts here', 'Notes, conversations and updates will appear as you work.') : A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('activity-feed')
										]),
									A2($elm$core$List$map, activityRow, stats.df))
								]))
						]))
				]));
	}
};
var $author$project$State$AdvanceClicked = function (a) {
	return {$: 69, a: a};
};
var $author$project$State$ConvertClicked = function (a) {
	return {$: 71, a: a};
};
var $author$project$State$DeleteLeadConfirmed = function (a) {
	return {$: 67, a: a};
};
var $author$project$State$EditLeadToggled = {$: 63};
var $author$project$State$UploadLeadDocClicked = function (a) {
	return {$: 117, a: a};
};
var $author$project$State$SubmitAddTaskFor = function (a) {
	return {$: 95, a: a};
};
var $author$project$Views$addTaskInline = F2(
	function (model, leadId) {
		return A2(
			$author$project$Views$taskComposer,
			model,
			$author$project$State$SubmitAddTaskFor(leadId));
	});
var $author$project$Views$contactGrid = function (detail) {
	var l = detail.aO;
	var kv = F2(
		function (k, v) {
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('kv')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(k)
							])),
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(v)
							]))
					]));
		});
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('kv-grid')
			]),
		_List_fromArray(
			[
				A2(
				kv,
				'Email',
				A2($elm$core$Maybe$withDefault, '—', l.ap)),
				A2(
				kv,
				'Phone',
				A2($elm$core$Maybe$withDefault, '—', l.bZ)),
				A2(
				kv,
				'Source',
				A2($elm$core$Maybe$withDefault, '—', l.ah)),
				A2(
				kv,
				'Destination',
				A2($elm$core$Maybe$withDefault, '—', l.aJ)),
				A2(
				kv,
				'Service',
				A2($elm$core$Maybe$withDefault, '—', l.ae)),
				A2(
				kv,
				'Consultant',
				A2($elm$core$Maybe$withDefault, '—', l.cF)),
				A2(
				kv,
				'Last Contact',
				$author$project$Ui$fmtDate(l.aN)),
				A2(
				kv,
				'Next Follow-up',
				$author$project$Ui$fmtDate(l._)),
				A2(
				kv,
				'Notes',
				A2($elm$core$Maybe$withDefault, '—', l.aa))
			]));
};
var $author$project$State$SubmitEditLead = {$: 65};
var $author$project$State$UpdateEditLead = function (a) {
	return {$: 64, a: a};
};
var $author$project$Types$qualities = _List_fromArray(
	['Hot', 'Warm', 'Cold']);
var $author$project$Types$sources = _List_fromArray(
	['Website', 'Facebook', 'Instagram', 'WhatsApp', 'Referring Agent', 'School Partner', 'Walk-in', 'Referral']);
var $author$project$Views$editLeadForm = F2(
	function (model, f) {
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A4(
					$author$project$Ui$inputField,
					'Full Name',
					f.bK,
					'text',
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{bK: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Email',
					f.ap,
					'email',
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{ap: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Phone',
					f.bZ,
					'text',
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{bZ: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Stage',
					$author$project$Types$leadStages,
					f.$7,
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{$7: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Quality',
					$author$project$Types$qualities,
					f.ad,
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{ad: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Source',
					$author$project$Types$sources,
					f.ah,
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{ah: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Destination',
					$author$project$Types$destinations,
					f.aJ,
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{aJ: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Service',
					$author$project$Types$services,
					f.ae,
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{ae: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Last Contact',
					f.aN,
					'date',
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{aN: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Next Follow-up',
					f._,
					'date',
					function (v) {
						return $author$project$State$UpdateEditLead(
							function (g) {
								return _Utils_update(
									g,
									{_: v});
							});
					}),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-group'),
							A2($elm$html$Html$Attributes$style, 'grid-column', '1 / -1')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$label,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Notes')
								])),
							A2(
							$elm$html$Html$textarea,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('input'),
									$elm$html$Html$Attributes$rows(3),
									$elm$html$Html$Attributes$value(f.aa),
									$elm$html$Html$Events$onInput(
									function (v) {
										return $author$project$State$UpdateEditLead(
											function (g) {
												return _Utils_update(
													g,
													{aa: v});
											});
									})
								]),
							_List_Nil)
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('flex'),
							A2($elm$html$Html$Attributes$style, 'grid-column', '1 / -1'),
							A2($elm$html$Html$Attributes$style, 'margin-top', '8px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$disabled(
									$author$project$Views$isReadOnly(model)),
									$elm$html$Html$Attributes$class('btn btn-primary'),
									$elm$html$Html$Events$onClick($author$project$State$SubmitEditLead)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Save Changes')
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$disabled(
									$author$project$Views$isReadOnly(model)),
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Events$onClick($author$project$State$EditLeadToggled)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Cancel')
								]))
						]))
				]));
	});
var $author$project$State$NoteDraftChanged = function (a) {
	return {$: 73, a: a};
};
var $author$project$State$NoteSubmitted = function (a) {
	return {$: 74, a: a};
};
var $author$project$Views$noteComposer = F2(
	function (model, leadId) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('add-note'),
					A2($elm$html$Html$Attributes$style, 'margin-bottom', '12px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('input'),
							$elm$html$Html$Attributes$placeholder('Log a note, call summary…'),
							$elm$html$Html$Attributes$value(model.aS),
							$elm$html$Html$Events$onInput($author$project$State$NoteDraftChanged)
						]),
					_List_Nil),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$disabled(
							$author$project$Views$isReadOnly(model)),
							$elm$html$Html$Attributes$class('btn btn-sm btn-primary'),
							$elm$html$Html$Events$onClick(
							$author$project$State$NoteSubmitted(leadId))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Add Note')
						]))
				]));
	});
var $author$project$Ui$qualityTag = function (q) {
	if (!q.$) {
		var quality = q.a;
		var cls = function () {
			var _v1 = $elm$core$String$toLower(quality);
			switch (_v1) {
				case 'hot':
					return 'tag tag-hot';
				case 'warm':
					return 'tag tag-warm';
				case 'cold':
					return 'tag tag-cold';
				default:
					return 'tag tag-cold';
			}
		}();
		return A2(
			$elm$html$Html$span,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class(cls)
				]),
			_List_fromArray(
				[
					$elm$html$Html$text(quality)
				]));
	} else {
		return A2($elm$html$Html$span, _List_Nil, _List_Nil);
	}
};
var $author$project$Ui$stageClass = function (stage) {
	switch (stage) {
		case 'Converted':
			return 'tag tag-converted';
		case 'Closed/Lost':
			return 'tag tag-lost';
		default:
			return 'tag tag-stage-blue';
	}
};
var $author$project$Ui$stageTag = function (stage) {
	return A2(
		$elm$html$Html$span,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class(
				$author$project$Ui$stageClass(stage))
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(stage)
			]));
};
var $author$project$Views$timeline = function (activities) {
	return $elm$core$List$isEmpty(activities) ? $author$project$Ui$emptyNote('No activity recorded.') : A2(
		$elm$html$Html$div,
		_List_Nil,
		A2(
			$elm$core$List$map,
			function (act) {
				return A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('tl-item')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('tl-date')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(act.cI)
								])),
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('tl-type')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(act.c_)
								])),
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('activity-desc')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									A2($elm$core$Maybe$withDefault, '', act.a4))
								]))
						]));
			},
			activities));
};
var $author$project$Views$leadDetailView = F2(
	function (model, id) {
		var _v0 = model.x;
		if (_v0.$ === 1) {
			return $author$project$Ui$spinner;
		} else {
			var detail = _v0.a;
			var l = detail.aO;
			return A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$a,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('back-link'),
								$elm$html$Html$Attributes$href('#'),
								$elm$html$Html$Events$onClick(
								$author$project$State$NavigateTo('/leads'))
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('← Back to Leads')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('page-head')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h2,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(l.bK)
											])),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('lead-detail-badges')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$span,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('tag tag-id')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(l.bV)
													])),
												$author$project$Ui$stageTag(l.$7),
												$author$project$Ui$qualityTag(l.ad)
											]))
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('flex')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn'),
												$elm$html$Html$Events$onClick($author$project$State$EditLeadToggled)
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												model.a5 ? 'Close Editor' : 'Edit')
											])),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn'),
												$elm$html$Html$Events$onClick(
												$author$project$State$AdvanceClicked(l.a9))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Advance ▸')
											])),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn btn-success'),
												$elm$html$Html$Events$onClick(
												A2(
													$author$project$State$ConfirmRequested,
													'Convert this lead to a client? Documents, tasks and the journey history will be preserved.',
													$author$project$State$ConvertClicked(l.a9)))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Convert to Client')
											])),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn btn-danger'),
												$elm$html$Html$Events$onClick(
												A2(
													$author$project$State$ConfirmRequested,
													'Move this lead to the archive? Its history will be preserved.',
													$author$project$State$DeleteLeadConfirmed(l.a9)))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Delete')
											]))
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('detail-grid')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('card')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('section-head')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$h3,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Contact & Pipeline')
													]))
											])),
										model.a5 ? A2($author$project$Views$editLeadForm, model, model.N) : $author$project$Views$contactGrid(detail)
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('card')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('section-head')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$h3,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Tasks')
													])),
												A2(
												$elm$html$Html$button,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
														$elm$html$Html$Events$onClick(
														$author$project$State$UpdateAddTask(
															function (f) {
																return _Utils_update(
																	f,
																	{ay: f.ay});
															}))
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('+')
													]))
											])),
										A2($author$project$Views$addTaskInline, model, id),
										A2($author$project$Views$taskRows, model, detail.J)
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('detail-grid'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
							]),
						_List_fromArray(
							[
								A3(
								$author$project$Views$documentsCard,
								model,
								detail.bC,
								$author$project$State$UploadLeadDocClicked(id))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('card'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('section-head')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h3,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text('Activity Timeline')
											]))
									])),
								A2($author$project$Views$noteComposer, model, id),
								$author$project$Views$timeline(detail.bu)
							]))
					]));
		}
	});
var $author$project$State$CloseAddLead = {$: 59};
var $author$project$State$SubmitAddLead = {$: 61};
var $author$project$State$UpdateAddLead = function (a) {
	return {$: 60, a: a};
};
var $author$project$Views$addLeadModal = function (model) {
	var f = model.aC;
	return A2(
		$author$project$Ui$modal,
		'Add Lead',
		A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A4(
					$author$project$Ui$inputField,
					'Full Name *',
					f.bK,
					'text',
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{bK: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Email',
					f.ap,
					'email',
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{ap: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Phone',
					f.bZ,
					'text',
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{bZ: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Source',
					$author$project$Types$sources,
					f.ah,
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{ah: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Quality',
					$author$project$Types$qualities,
					f.ad,
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{ad: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Stage',
					$author$project$Types$leadStages,
					f.$7,
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{$7: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Destination',
					$author$project$Types$destinations,
					f.aJ,
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{aJ: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Service',
					$author$project$Types$services,
					f.ae,
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{ae: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Next Follow-up',
					f._,
					'date',
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{_: v});
							});
					}),
					A4(
					$author$project$Ui$inputField,
					'Notes',
					f.aa,
					'text',
					function (v) {
						return $author$project$State$UpdateAddLead(
							function (g) {
								return _Utils_update(
									g,
									{aa: v});
							});
					}),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('flex'),
							A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$disabled(
									$author$project$Views$isReadOnly(model)),
									$elm$html$Html$Attributes$class('btn btn-primary'),
									$elm$html$Html$Events$onClick($author$project$State$SubmitAddLead)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Save Lead')
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Events$onClick($author$project$State$CloseAddLead)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Cancel')
								]))
						]))
				])));
};
var $author$project$State$BulkAdvanceClicked = {$: 85};
var $author$project$State$BulkAssignPicked = function (a) {
	return {$: 86, a: a};
};
var $author$project$State$BulkDeleteClicked = {$: 87};
var $elm$core$Dict$isEmpty = function (dict) {
	if (dict.$ === -2) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Set$isEmpty = function (_v0) {
	var dict = _v0;
	return $elm$core$Dict$isEmpty(dict);
};
var $elm$core$Dict$sizeHelp = F2(
	function (n, dict) {
		sizeHelp:
		while (true) {
			if (dict.$ === -2) {
				return n;
			} else {
				var left = dict.d;
				var right = dict.e;
				var $temp$n = A2($elm$core$Dict$sizeHelp, n + 1, right),
					$temp$dict = left;
				n = $temp$n;
				dict = $temp$dict;
				continue sizeHelp;
			}
		}
	});
var $elm$core$Dict$size = function (dict) {
	return A2($elm$core$Dict$sizeHelp, 0, dict);
};
var $elm$core$Set$size = function (_v0) {
	var dict = _v0;
	return $elm$core$Dict$size(dict);
};
var $author$project$Views$bulkBar = function (model) {
	return $elm$core$Set$isEmpty(model.v) ? A2($elm$html$Html$div, _List_Nil, _List_Nil) : A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('bulk-actions')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$strong,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(
						$elm$core$String$fromInt(
							$elm$core$Set$size(model.v)) + ' selected')
					])),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$disabled(
						$author$project$Views$isReadOnly(model)),
						$elm$html$Html$Attributes$class('btn btn-sm btn-success'),
						$elm$html$Html$Events$onClick($author$project$State$BulkAdvanceClicked)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Advance')
					])),
				A2(
				$elm$html$Html$select,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$disabled(
						$author$project$Views$isReadOnly(model)),
						$elm$html$Html$Events$onInput($author$project$State$BulkAssignPicked)
					]),
				A2(
					$elm$core$List$cons,
					A2(
						$elm$html$Html$option,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$value('')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Assign consultant…')
							])),
					A2(
						$elm$core$List$map,
						function (u) {
							return A2(
								$elm$html$Html$option,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$value(
										$elm$core$String$fromInt(u.a9))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(u.t)
									]));
						},
						model.T))),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$disabled(
						$author$project$Views$isReadOnly(model)),
						$elm$html$Html$Attributes$class('btn btn-sm btn-danger'),
						$elm$html$Html$Events$onClick(
						A2($author$project$State$ConfirmRequested, 'Archive the selected leads and preserve their history?', $author$project$State$BulkDeleteClicked))
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Delete')
					]))
			]));
};
var $author$project$State$RowChecked = F2(
	function (a, b) {
		return {$: 83, a: a, b: b};
	});
var $author$project$State$SelectAllChecked = function (a) {
	return {$: 84, a: a};
};
var $elm$core$List$all = F2(
	function (isOkay, list) {
		return !A2(
			$elm$core$List$any,
			A2($elm$core$Basics$composeL, $elm$core$Basics$not, isOkay),
			list);
	});
var $elm$html$Html$Attributes$checked = $elm$html$Html$Attributes$boolProperty('checked');
var $elm$core$Dict$member = F2(
	function (key, dict) {
		var _v0 = A2($elm$core$Dict$get, key, dict);
		if (!_v0.$) {
			return true;
		} else {
			return false;
		}
	});
var $elm$core$Set$member = F2(
	function (key, _v0) {
		var dict = _v0;
		return A2($elm$core$Dict$member, key, dict);
	});
var $elm$html$Html$Events$targetChecked = A2(
	$elm$json$Json$Decode$at,
	_List_fromArray(
		['target', 'checked']),
	$elm$json$Json$Decode$bool);
var $elm$html$Html$Events$onCheck = function (tagger) {
	return A2(
		$elm$html$Html$Events$on,
		'change',
		A2($elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetChecked));
};
var $author$project$Views$leadsTable = function (model) {
	var row = function (l) {
		return A2(
			$elm$html$Html$tr,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$type_('checkbox'),
									$elm$html$Html$Attributes$class('row-check'),
									A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Select ' + l.bK),
									$elm$html$Html$Attributes$checked(
									A2($elm$core$Set$member, l.a9, model.v)),
									A2(
									$elm$html$Html$Events$stopPropagationOn,
									'click',
									$elm$json$Json$Decode$succeed(
										_Utils_Tuple2(
											A2(
												$author$project$State$RowChecked,
												l.a9,
												!A2($elm$core$Set$member, l.a9, model.v)),
											true)))
								]),
							_List_Nil)
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$html$Html$a,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('contact-identity'),
									$elm$html$Html$Attributes$href(
									'/leads/' + $elm$core$String$fromInt(l.a9))
								]),
							_List_fromArray(
								[
									$author$project$Ui$avatar(l.bK),
									A2(
									$elm$html$Html$div,
									_List_Nil,
									_List_fromArray(
										[
											A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('lead-name')
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(l.bK)
												])),
											A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('lead-source')
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(
													A2($elm$core$Maybe$withDefault, 'No email added', l.ap))
												]))
										]))
								]))
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(l.bV)
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$author$project$Ui$stageTag(l.$7)
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$author$project$Ui$qualityTag(l.ad)
						])),
					A2(
					$elm$html$Html$td,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('lead-source')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($elm$core$Maybe$withDefault, '—', l.ah))
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							A2($elm$core$Maybe$withDefault, '—', l.cF))
						])),
					A2(
					$elm$html$Html$td,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							$author$project$Ui$fmtDate(l._))
						]))
				]));
	};
	var leads = $author$project$Views$filteredLeads(model);
	var allChecked = (!$elm$core$List$isEmpty(leads)) && A2(
		$elm$core$List$all,
		function (l) {
			return A2($elm$core$Set$member, l.a9, model.v);
		},
		leads);
	return $elm$core$List$isEmpty(leads) ? A3($author$project$Ui$emptyState, 'search', 'No leads to show', 'Try a different search or adjust your filters. Add a lead to start a new relationship.') : A2(
		$elm$html$Html$table,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('data-table leads-table')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$thead,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$tr,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$input,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$type_('checkbox'),
												$elm$html$Html$Attributes$class('row-check'),
												A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Select all leads on this page'),
												$elm$html$Html$Attributes$checked(allChecked),
												$elm$html$Html$Events$onCheck($author$project$State$SelectAllChecked)
											]),
										_List_Nil)
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Lead')
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Number')
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Stage')
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Quality')
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Source')
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Consultant')
									])),
								A2(
								$elm$html$Html$th,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Follow-up')
									]))
							]))
					])),
				A2(
				$elm$html$Html$tbody,
				_List_Nil,
				A2($elm$core$List$map, row, leads))
			]));
};
var $author$project$State$ImportFilePicked = function (a) {
	return {$: 123, a: a};
};
var $author$project$State$LeadImportClicked = {$: 124};
var $author$project$State$OpenAddLead = {$: 58};
var $author$project$State$QualityFilterChanged = function (a) {
	return {$: 78, a: a};
};
var $author$project$State$SearchChanged = function (a) {
	return {$: 76, a: a};
};
var $author$project$State$SortByChanged = function (a) {
	return {$: 80, a: a};
};
var $author$project$State$SortDirToggled = {$: 81};
var $author$project$State$SourceFilterChanged = function (a) {
	return {$: 79, a: a};
};
var $author$project$State$StageFilterChanged = function (a) {
	return {$: 77, a: a};
};
var $author$project$Views$leadsToolbar = function (model) {
	var ctx = {M: model.ak, du: model.du};
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('search-container')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('search-row')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('search-input-wrapper')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$input,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('search-input'),
										A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Search leads'),
										$elm$html$Html$Attributes$placeholder('Search name, email, phone, lead number…'),
										$elm$html$Html$Attributes$value(model.dc),
										$elm$html$Html$Events$onInput($author$project$State$SearchChanged)
									]),
								_List_Nil)
							])),
						A2(
						$elm$html$Html$a,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn btn-outline'),
								$elm$html$Html$Attributes$href(
								A2($author$project$Api$exportCsvUrl, ctx, 'leads')),
								$elm$html$Html$Attributes$download('')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Export CSV')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('import-group')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$input,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$disabled(
										$author$project$Views$isReadOnly(model)),
										$elm$html$Html$Attributes$type_('file'),
										A2($elm$html$Html$Attributes$attribute, 'accept', '.csv,text/csv'),
										$elm$html$Html$Attributes$title('Pick a CSV of leads to import'),
										A2(
										$elm$html$Html$Events$on,
										'change',
										A2(
											$elm$json$Json$Decode$map,
											$author$project$State$ImportFilePicked,
											A2(
												$elm$json$Json$Decode$at,
												_List_fromArray(
													['target', 'files']),
												A2($elm$json$Json$Decode$index, 0, $elm$file$File$decoder))))
									]),
								_List_Nil),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$disabled(
										$author$project$Views$isReadOnly(model)),
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Attributes$title(
										function () {
											var _v0 = model.aU;
											if (!_v0.$) {
												var f = _v0.a;
												return 'Import ' + $elm$file$File$name(f);
											} else {
												return 'Import leads from the selected CSV file';
											}
										}()),
										$elm$html$Html$Events$onClick($author$project$State$LeadImportClicked)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										function () {
											var _v1 = model.aU;
											if (!_v1.$) {
												var f = _v1.a;
												return 'Import (' + ($elm$file$File$name(f) + ')');
											} else {
												return 'Import';
											}
										}())
									]))
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$disabled(
								$author$project$Views$isReadOnly(model)),
								$elm$html$Html$Attributes$class('btn btn-primary'),
								$elm$html$Html$Events$onClick($author$project$State$OpenAddLead)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('+ Add Lead')
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('filter-row')
					]),
				_List_fromArray(
					[
						A4(
						$author$project$Views$selectFieldMsg,
						'Stage',
						$author$project$Views$plainOptions(
							A2($elm$core$List$cons, 'All', $author$project$Types$leadStages)),
						model.cS,
						$author$project$State$StageFilterChanged),
						A4(
						$author$project$Views$selectFieldMsg,
						'Quality',
						$author$project$Views$plainOptions(
							A2($elm$core$List$cons, 'All', $author$project$Types$qualities)),
						model.cQ,
						$author$project$State$QualityFilterChanged),
						A4(
						$author$project$Views$selectFieldMsg,
						'Source',
						$author$project$Views$plainOptions(
							A2($elm$core$List$cons, 'All', $author$project$Types$sources)),
						model.cR,
						$author$project$State$SourceFilterChanged),
						A4(
						$author$project$Views$selectFieldMsg,
						'Sort By',
						_List_fromArray(
							[
								_Utils_Tuple2('name', 'Name'),
								_Utils_Tuple2('stage', 'Stage'),
								_Utils_Tuple2('quality', 'Quality'),
								_Utils_Tuple2('followup', 'Follow-up')
							]),
						model.dm,
						$author$project$State$SortByChanged),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('filter-group')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$label,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Direction')
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										A2($elm$html$Html$Attributes$style, 'width', '100%'),
										$elm$html$Html$Events$onClick($author$project$State$SortDirToggled)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										model.dl ? '↑ Ascending' : '↓ Descending')
									]))
							]))
					]))
			]));
};
var $author$project$Views$leadsView = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('page-head')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('Leads')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('results-summary')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$elm$core$String$fromInt(
									$elm$core$List$length(
										$author$project$Views$filteredLeads(model))) + ' shown')
							]))
					])),
				$author$project$Views$leadsToolbar(model),
				$author$project$Views$bulkBar(model),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('card table-card'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '12px')
					]),
				_List_fromArray(
					[
						$author$project$Views$leadsTable(model)
					])),
				model.bn ? $author$project$Views$addLeadModal(model) : A2($elm$html$Html$div, _List_Nil, _List_Nil)
			]));
};
var $author$project$State$ToggleGlobalAddTask = {$: 93};
var $author$project$State$SubmitAddTaskGlobal = {$: 97};
var $author$project$Views$globalAddTaskForm = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('card'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '16px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('inline-form')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('form-group'),
								A2($elm$html$Html$Attributes$style, 'flex', '1.5')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$label,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Lead or client')
									])),
								A2(
								$elm$html$Html$select,
								_List_fromArray(
									[
										$elm$html$Html$Events$onInput(
										function (v) {
											return $author$project$State$UpdateAddTask(
												function (f) {
													return _Utils_update(
														f,
														{aP: v});
												});
										})
									]),
								A2(
									$elm$core$List$cons,
									A2(
										$elm$html$Html$option,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$value('')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Choose a lead or client…')
											])),
									_Utils_ap(
										A2(
											$elm$core$List$map,
											function (l) {
												return A2(
													$elm$html$Html$option,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$value(
															$elm$core$String$fromInt(l.a9)),
															$elm$html$Html$Attributes$selected(
															_Utils_eq(
																model.k.aP,
																$elm$core$String$fromInt(l.a9)))
														]),
													_List_fromArray(
														[
															$elm$html$Html$text(l.bV + (' — ' + l.bK))
														]));
											},
											model.P),
										A2(
											$elm$core$List$map,
											function (client) {
												return A2(
													$elm$html$Html$option,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$value(
															'client:' + $elm$core$String$fromInt(client.a9)),
															$elm$html$Html$Attributes$selected(
															_Utils_eq(
																model.k.aP,
																'client:' + $elm$core$String$fromInt(client.a9)))
														]),
													_List_fromArray(
														[
															$elm$html$Html$text('Client · ' + client.bK)
														]));
											},
											model.am))))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('form-group'),
								A2($elm$html$Html$Attributes$style, 'flex', '2')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$input,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('input'),
										$elm$html$Html$Attributes$placeholder('Task title…'),
										$elm$html$Html$Attributes$value(model.k.ay),
										$elm$html$Html$Events$onInput(
										function (v) {
											return $author$project$State$UpdateAddTask(
												function (f) {
													return _Utils_update(
														f,
														{ay: v});
												});
										})
									]),
								_List_Nil)
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('form-group')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$input,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$type_('date'),
										$elm$html$Html$Attributes$class('input'),
										$elm$html$Html$Attributes$value(model.k.aK),
										$elm$html$Html$Events$onInput(
										function (v) {
											return $author$project$State$UpdateAddTask(
												function (f) {
													return _Utils_update(
														f,
														{aK: v});
												});
										})
									]),
								_List_Nil)
							])),
						A4(
						$author$project$Views$selectFieldMsg,
						'',
						$author$project$Views$plainOptions($author$project$Types$priorities),
						model.k.bl,
						function (v) {
							return $author$project$State$UpdateAddTask(
								function (f) {
									return _Utils_update(
										f,
										{bl: v});
								});
						}),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$disabled(
								$author$project$Views$isReadOnly(model)),
								$elm$html$Html$Attributes$class('btn btn-primary'),
								$elm$html$Html$Events$onClick($author$project$State$SubmitAddTaskGlobal)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Create')
							]))
					]))
			]));
};
var $author$project$Views$tasksView = function (model) {
	var section = function (status) {
		var items = A2(
			$elm$core$List$filter,
			function (t) {
				return _Utils_eq(t.dr, status);
			},
			model.J);
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class(
					'card task-column task-column-' + $elm$core$String$toLower(
						A3($elm$core$String$replace, ' ', '-', status)))
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('section-head')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$h3,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('status-dot'),
											A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true')
										]),
									_List_Nil),
									$elm$html$Html$text(status)
								])),
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('lead-count')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									$elm$core$String$fromInt(
										$elm$core$List$length(items)))
								]))
						])),
					$elm$core$List$isEmpty(items) ? A3($author$project$Ui$emptyState, 'check', 'Nothing here yet', 'Tasks appear here as work moves forward.') : A2(
					$elm$html$Html$div,
					_List_Nil,
					A2(
						$elm$core$List$map,
						function (t) {
							return A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('task-row')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$select,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												A2($elm$html$Html$Attributes$style, 'padding', '4px'),
												A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Status for ' + t.ay),
												$elm$html$Html$Events$onInput(
												$author$project$State$TaskStatusPicked(t.a9))
											]),
										A2(
											$elm$core$List$map,
											function (s) {
												return A2(
													$elm$html$Html$option,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$value(s),
															$elm$html$Html$Attributes$selected(
															_Utils_eq(s, t.dr))
														]),
													_List_fromArray(
														[
															$elm$html$Html$text(s)
														]));
											},
											$author$project$Types$taskStatuses)),
										A2(
										$elm$html$Html$span,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class(
												(t.dr === 'Done') ? 'done-title' : '')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$strong,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text(t.ay)
													]))
											])),
										A2(
										$elm$html$Html$a,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('task-lead'),
												$elm$html$Html$Attributes$href('#'),
												$elm$html$Html$Events$onClick(
												$author$project$State$NavigateTo(
													A2(
														$elm$core$Maybe$withDefault,
														'/leads/' + $elm$core$String$fromInt(t.aP),
														A2(
															$elm$core$Maybe$map,
															function (id) {
																return '/clients/' + $elm$core$String$fromInt(id);
															},
															t.a1))))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2($elm$core$Maybe$withDefault, '', t.bS))
											])),
										$author$project$Ui$priorityBadge(t.bl),
										A2(
										$elm$html$Html$span,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('activity-date')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												$author$project$Ui$fmtDate(t.aK))
											])),
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$disabled(
												$author$project$Views$isReadOnly(model)),
												$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
												$elm$html$Html$Events$onClick(
												A2(
													$author$project$State$ConfirmRequested,
													'Delete this task? This action cannot be undone.',
													$author$project$State$TaskDeleted(t.a9)))
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('✕')
											]))
									]));
						},
						items))
				]));
	};
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('page-head')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('Tasks')
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$disabled(
								$author$project$Views$isReadOnly(model)),
								$elm$html$Html$Attributes$class('btn btn-primary'),
								$elm$html$Html$Events$onClick($author$project$State$ToggleGlobalAddTask)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								model.bo ? 'Close' : '+ New Task')
							]))
					])),
				model.bo ? $author$project$Views$globalAddTaskForm(model) : A2($elm$html$Html$div, _List_Nil, _List_Nil),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('task-board')
					]),
				_List_fromArray(
					[
						section('Pending'),
						section('In Progress'),
						section('Done')
					]))
			]));
};
var $author$project$State$DeleteUserConfirmed = function (a) {
	return {$: 133, a: a};
};
var $author$project$State$OpenAddUser = {$: 126};
var $author$project$State$OpenUserEditor = function (a) {
	return {$: 127, a: a};
};
var $author$project$State$RunOperation = function (a) {
	return {$: 13, a: a};
};
var $author$project$Views$usersView = function (model) {
	var me_ = A2(
		$elm$core$Maybe$withDefault,
		{ap: '', a9: 0, bf: false, t: '', m: 1, aX: ''},
		model.a$);
	if (me_.aX !== 'admin') {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('card')
				]),
			_List_fromArray(
				[
					$author$project$Ui$emptyNote('Admin access required.')
				]));
	} else {
		var userRow = function (u) {
			return A2(
				$elm$html$Html$tr,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(u.t)
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(u.ap)
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class(
										(u.aX === 'admin') ? 'tag tag-hot' : ((u.aX === 'viewer') ? 'tag tag-cold' : 'tag tag-warm'))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(u.aX)
									]))
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
										$elm$html$Html$Events$onClick(
										$author$project$State$OpenUserEditor(u.a9))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Edit')
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
										$elm$html$Html$Events$onClick(
										$author$project$State$RunOperation(
											'users/' + ($elm$core$String$fromInt(u.a9) + '/invite')))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Send invitation')
									]))
							])),
						A2(
						$elm$html$Html$td,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-sm btn-danger'),
										$elm$html$Html$Events$onClick(
										A2(
											$author$project$State$ConfirmRequested,
											'Delete this account and revoke its sessions? Existing activity will remain in the audit trail.',
											$author$project$State$DeleteUserConfirmed(u.a9))),
										$elm$html$Html$Attributes$disabled(
										_Utils_eq(u.a9, me_.a9))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										_Utils_eq(u.a9, me_.a9) ? 'You' : 'Delete')
									]))
							]))
					]));
		};
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('page-head')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h2,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text('Users')
										])),
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('empty-note')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Admins manage accounts. Viewers are read-only.')
										]))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('flex')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('btn btn-primary'),
											$elm$html$Html$Events$onClick($author$project$State$OpenAddUser)
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('+ Add User')
										]))
								]))
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('card table-card')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$table,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('data-table')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$thead,
									_List_Nil,
									_List_fromArray(
										[
											A2(
											$elm$html$Html$tr,
											_List_Nil,
											_List_fromArray(
												[
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Name')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Email')
														])),
													A2(
													$elm$html$Html$th,
													_List_Nil,
													_List_fromArray(
														[
															$elm$html$Html$text('Role')
														])),
													A2($elm$html$Html$th, _List_Nil, _List_Nil),
													A2($elm$html$Html$th, _List_Nil, _List_Nil)
												]))
										])),
									A2(
									$elm$html$Html$tbody,
									_List_Nil,
									A2($elm$core$List$map, userRow, model.T))
								]))
						]))
				]));
	}
};
var $author$project$Operations$flag = F2(
	function (key, value) {
		return A2(
			$elm$core$Result$withDefault,
			false,
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, key, $elm$json$Json$Decode$bool),
				value));
	});
var $author$project$Operations$metric = F2(
	function (label, value) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('stat')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('stat-label')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label)
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('stat-value')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							$elm$core$String$fromInt(value))
						]))
				]));
	});
var $author$project$Operations$num = F2(
	function (key, value) {
		return A2(
			$elm$core$Result$withDefault,
			0,
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, key, $elm$json$Json$Decode$int),
				value));
	});
var $author$project$Operations$str = F2(
	function (key, value) {
		return A2(
			$elm$core$Result$withDefault,
			'—',
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, key, $elm$json$Json$Decode$string),
				value));
	});
var $author$project$Operations$view = F2(
	function (model, kind) {
		var row = function (item) {
			switch (kind) {
				case 'archive':
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('operation-row')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$span,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('eyebrow')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2($author$project$Operations$str, 'kind', item) + (' / ' + A2($author$project$Operations$str, 'number', item)))
											])),
										A2(
										$elm$html$Html$h3,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2($author$project$Operations$str, 'name', item))
											])),
										A2(
										$elm$html$Html$p,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('text-muted')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												'Archived ' + A2(
													$elm$core$String$left,
													10,
													A2($author$project$Operations$str, 'date', item)))
											]))
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Events$onClick(
										$author$project$State$RunOperation(
											((A2($author$project$Operations$str, 'kind', item) === 'lead') ? 'leads/' : 'clients/') + ($elm$core$String$fromInt(
												A2($author$project$Operations$num, 'id', item)) + '/restore')))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Restore record ↗')
									]))
							]));
				case 'duplicates':
					var records = A2(
						$elm$core$Result$withDefault,
						_List_Nil,
						A2(
							$elm$json$Json$Decode$decodeValue,
							A2(
								$elm$json$Json$Decode$field,
								'records',
								$elm$json$Json$Decode$list($elm$json$Json$Decode$value)),
							item));
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('operation-row')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$span,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('eyebrow')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												'MATCHING ' + $elm$core$String$toUpper(
													A2($author$project$Operations$str, 'field', item)))
											])),
										A2(
										$elm$html$Html$h3,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2($author$project$Operations$str, 'value', item))
											]))
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('duplicate-links')
									]),
								A2(
									$elm$core$List$map,
									function (record) {
										return A2(
											$elm$html$Html$a,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('btn btn-outline'),
													$elm$html$Html$Attributes$href(
													_Utils_ap(
														(A2($author$project$Operations$str, 'kind', record) === 'lead') ? '/leads/' : '/clients/',
														$elm$core$String$fromInt(
															A2($author$project$Operations$num, 'id', record))))
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(
													A2($author$project$Operations$str, 'name', record) + ' ↗')
												]));
									},
									records))
							]));
				case 'metrics':
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('stats')
							]),
						_List_fromArray(
							[
								A2(
								$author$project$Operations$metric,
								'Pending emails',
								A2($author$project$Operations$num, 'pendingMail', item)),
								A2(
								$author$project$Operations$metric,
								'Failed deliveries',
								A2($author$project$Operations$num, 'failedMail', item)),
								A2(
								$author$project$Operations$metric,
								'Active sessions',
								A2($author$project$Operations$num, 'activeSessions', item)),
								A2(
								$author$project$Operations$metric,
								'Database · MB',
								(A2($author$project$Operations$num, 'databaseBytes', item) / 1048576) | 0)
							]));
				default:
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class(
								A2($author$project$Operations$flag, 'read', item) ? 'operation-row reminder-read' : 'operation-row')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$span,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('eyebrow')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												$elm$core$String$toUpper(
													A2($author$project$Operations$str, 'kind', item)) + (' / DUE ' + A2($author$project$Operations$str, 'due', item)))
											])),
										A2(
										$elm$html$Html$h3,
										_List_Nil,
										_List_fromArray(
											[
												A2(
												$elm$html$Html$a,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$href(
														A2($author$project$Operations$str, 'path', item))
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(
														A2($author$project$Operations$str, 'title', item))
													]))
											]))
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-outline'),
										$elm$html$Html$Attributes$disabled(
										A2($author$project$Operations$flag, 'read', item)),
										$elm$html$Html$Events$onClick(
										$author$project$State$RunOperation(
											'reminders/' + (A2($author$project$Operations$str, 'kind', item) + ('/' + ($elm$core$String$fromInt(
												A2($author$project$Operations$num, 'id', item)) + '/read')))))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										A2($author$project$Operations$flag, 'read', item) ? '✓ Read' : 'Mark as read')
									]))
							]));
			}
		};
		var _v0 = function () {
			switch (kind) {
				case 'archive':
					return _Utils_Tuple3('Archive', 'Deleted leads and clients stay here with their history. Restore a record to continue working.', 'No archived records. Your workspace is up to date.');
				case 'duplicates':
					return _Utils_Tuple3('Possible duplicates', 'Review shared email addresses and phone numbers before creating another record.', 'No matching contacts found. Looking good.');
				case 'metrics':
					return _Utils_Tuple3('System overview', 'Delivery queue, database storage and active sessions. Failed email deliveries need attention.', 'No system information available.');
				default:
					return _Utils_Tuple3('Your reminders', 'Follow-ups and tasks due in the next seven days. Mark reminders as read without completing the underlying task.', 'You’re all caught up. No upcoming reminders.');
			}
		}();
		var title = _v0.a;
		var description = _v0.b;
		var empty = _v0.c;
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('page-head')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h2,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(title)
										])),
									A2(
									$elm$html$Html$p,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('page-description')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(description)
										]))
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Events$onClick(
									$author$project$State$NavigateTo(model.a_.A))
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Refresh ↻')
								]))
						])),
					model.c7 ? $author$project$Ui$spinner : (($elm$core$List$isEmpty(model.bY) && (model.j === '')) ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('empty-state card')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('empty-state-icon')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('✓')
								])),
							A2(
							$elm$html$Html$h3,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(empty)
								])),
							A2(
							$elm$html$Html$p,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Everything you need will appear here.')
								]))
						])) : A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('operations-list')
						]),
					A2($elm$core$List$map, row, model.bY)))
				]));
	});
var $author$project$Main$pageView = function (model) {
	var _v0 = $author$project$State$routeOf(model.a_);
	switch (_v0.$) {
		case 0:
			return $author$project$Views$dashboardView(model);
		case 1:
			return $author$project$Views$leadsView(model);
		case 2:
			var id = _v0.a;
			return A2($author$project$Views$leadDetailView, model, id);
		case 3:
			return $author$project$Views$clientsView(model);
		case 4:
			var id = _v0.a;
			return A2($author$project$Views$clientDetailView, model, id);
		case 5:
			return $author$project$Views$tasksView(model);
		case 6:
			return $author$project$Views$usersView(model);
		case 7:
			return $author$project$Views$auditView(model);
		default:
			var kind = _v0.a;
			return A2($elm$core$String$startsWith, 'work/', kind) ? A2(
				$author$project$Features$view,
				model,
				A2($elm$core$String$dropLeft, 5, kind)) : A2($author$project$Operations$view, model, kind);
	}
};
var $author$project$Main$pagination = function (model) {
	var size = function () {
		var _v1 = $author$project$State$routeOf(model.a_);
		switch (_v1.$) {
			case 1:
				return $elm$core$Maybe$Just(
					$elm$core$List$length(model.P));
			case 3:
				return $elm$core$Maybe$Just(
					$elm$core$List$length(model.am));
			case 5:
				return $elm$core$Maybe$Just(
					$elm$core$List$length(model.J));
			case 8:
				var kind = _v1.a;
				return (kind === 'metrics') ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
					$elm$core$List$length(model.bY));
			default:
				return $elm$core$Maybe$Nothing;
		}
	}();
	if (size.$ === 1) {
		return A2($elm$html$Html$span, _List_Nil, _List_Nil);
	} else {
		var count = size.a;
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('pagination'),
					A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Pagination')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							model.c7 ? 'Loading records…' : ($elm$core$String$fromInt(count) + (' records · page ' + $elm$core$String$fromInt(1 + ((model.c8 / 50) | 0)))))
						])),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-outline'),
							$elm$html$Html$Attributes$disabled((!model.c8) || model.c7),
							$elm$html$Html$Events$onClick(
							$author$project$State$PageStep(-1))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('← Previous')
						])),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('btn btn-outline'),
							$elm$html$Html$Attributes$disabled((count < 50) || model.c7),
							$elm$html$Html$Events$onClick(
							$author$project$State$PageStep(1))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Next →')
						]))
				]));
	}
};
var $author$project$State$PwConfirmChanged = function (a) {
	return {$: 138, a: a};
};
var $author$project$State$PwCurrentChanged = function (a) {
	return {$: 136, a: a};
};
var $author$project$State$PwNewChanged = function (a) {
	return {$: 137, a: a};
};
var $author$project$State$SubmitPasswordChange = {$: 139};
var $author$project$Views$passwordModal = function (model) {
	return A2(
		$author$project$Ui$modal,
		'Change Password',
		A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A4($author$project$Ui$inputField, 'Current Password', model.aW, 'password', $author$project$State$PwCurrentChanged),
					A4($author$project$Ui$inputField, 'New Password (min 12 characters)', model.ac, 'password', $author$project$State$PwNewChanged),
					A4($author$project$Ui$inputField, 'Confirm New Password', model.aV, 'password', $author$project$State$PwConfirmChanged),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('flex'),
							A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-primary'),
									$elm$html$Html$Events$onClick($author$project$State$SubmitPasswordChange)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Update Password')
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Events$onClick($author$project$State$TogglePwModal)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Cancel')
								]))
						]))
				])));
};
var $author$project$State$PortalFile = function (a) {
	return {$: 34, a: a};
};
var $author$project$State$PortalLogout = {$: 37};
var $author$project$State$PortalUpload = function (a) {
	return {$: 35, a: a};
};
var $author$project$Features$portalView = function (model) {
	var block = F3(
		function (name, key, render) {
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('card')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(name)
							])),
						A2(
						$elm$html$Html$div,
						_List_Nil,
						A2(
							$elm$core$List$map,
							render,
							A2($author$project$Features$items, key, model.c9)))
					]));
		});
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('container')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$h1,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text('Your client workspace')
					])),
				A2(
				$elm$html$Html$p,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(model.da)
					])),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('btn btn-outline'),
						$elm$html$Html$Events$onClick($author$project$State$PortalLogout)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Sign out')
					])),
				A3(
				block,
				'Your details',
				'client',
				function (item) {
					return A2(
						$elm$html$Html$p,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(
								A2($author$project$Features$str, 'name', item) + (' · ' + A2($author$project$Features$str, 'number', item)))
							]));
				}),
				A3(
				block,
				'Cases',
				'cases',
				function (item) {
					return A2(
						$elm$html$Html$p,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(
								A2($author$project$Features$str, 'title', item) + (' · ' + (A2($author$project$Features$str, 'stage', item) + (' · ' + A2($author$project$Features$str, 'deadline', item)))))
							]));
				}),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('form-group')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$label,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$for('portal-file')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Choose a file to submit')
							])),
						A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$id('portal-file'),
								$elm$html$Html$Attributes$type_('file'),
								A2(
								$elm$html$Html$Events$on,
								'change',
								A2(
									$elm$json$Json$Decode$map,
									$author$project$State$PortalFile,
									A2(
										$elm$json$Json$Decode$at,
										_List_fromArray(
											['target', 'files']),
										A2($elm$json$Json$Decode$index, 0, $elm$file$File$decoder))))
							]),
						_List_Nil)
					])),
				A3(
				block,
				'Document checklist',
				'checklist',
				function (item) {
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('operation-row')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h3,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2($author$project$Features$str, 'title', item))
											])),
										A2(
										$elm$html$Html$p,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2($author$project$Features$str, 'status', item) + (' · ' + A2($author$project$Features$str, 'feedback', item)))
											]))
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-primary'),
										$elm$html$Html$Attributes$disabled(
										_Utils_eq(model.db, $elm$core$Maybe$Nothing)),
										$elm$html$Html$Events$onClick(
										$author$project$State$PortalUpload(
											A2(
												$elm$core$Maybe$withDefault,
												0,
												$elm$core$String$toInt(
													A2($author$project$Features$str, 'id', item)))))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Submit selected file')
									]))
							]));
				}),
				A3(
				block,
				'Shared documents',
				'documents',
				function (item) {
					return A2(
						$elm$html$Html$a,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn btn-outline'),
								$elm$html$Html$Attributes$href(
								'/api/portal/documents/' + A2($author$project$Features$str, 'id', item))
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								A2($author$project$Features$str, 'title', item))
							]));
				}),
				A3(
				block,
				'Invoices',
				'invoices',
				function (item) {
					return A2(
						$elm$html$Html$p,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(
								'INV-' + (A2($author$project$Features$str, 'id', item) + (' · ' + (A2($author$project$Features$str, 'description', item) + (' · ' + (A2($author$project$Features$str, 'currency', item) + (' ' + (A2($author$project$Features$str, 'amount', item) + (' · ' + (A2($author$project$Features$str, 'status', item) + (' · Due ' + A2($author$project$Features$str, 'dueDate', item))))))))))))
							]));
				})
			]));
};
var $author$project$Views$toastStack = function (model) {
	return $elm$core$List$isEmpty(model.aZ) ? A2($elm$html$Html$span, _List_Nil, _List_Nil) : A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('toast-container')
			]),
		A2(
			$elm$core$List$map,
			function (t) {
				return A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class(
							'toast toast-' + function () {
								var _v0 = t.c_;
								switch (_v0) {
									case 'success':
										return 'success';
									case 'error':
										return 'error';
									default:
										return 'info';
								}
							}())
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(t.c0)
						]));
			},
			model.aZ));
};
var $author$project$State$CloseUserForm = {$: 128};
var $author$project$State$SubmitUserForm = {$: 130};
var $author$project$State$UpdateUserForm = function (a) {
	return {$: 129, a: a};
};
var $author$project$Types$roles = _List_fromArray(
	['admin', 'consultant', 'viewer']);
var $author$project$Views$userFormModal = function (model) {
	var f = model.B;
	var editing = !_Utils_eq(f.ch, $elm$core$Maybe$Nothing);
	var pwField = editing ? A4(
		$author$project$Ui$inputField,
		'Password (leave blank to keep current)',
		f.ab,
		'password',
		function (v) {
			return $author$project$State$UpdateUserForm(
				function (g) {
					return _Utils_update(
						g,
						{ab: v});
				});
		}) : A4(
		$author$project$Ui$inputField,
		'Password (12+ characters, or leave blank to email an invitation)',
		f.ab,
		'password',
		function (v) {
			return $author$project$State$UpdateUserForm(
				function (g) {
					return _Utils_update(
						g,
						{ab: v});
				});
		});
	return A2(
		$author$project$Ui$modal,
		editing ? 'Edit User' : 'Add User',
		A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A4(
					$author$project$Ui$inputField,
					'Full Name',
					f.t,
					'text',
					function (v) {
						return $author$project$State$UpdateUserForm(
							function (g) {
								return _Utils_update(
									g,
									{t: v});
							});
					}),
					editing ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('form-group')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$label,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Email')
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('input'),
									A2($elm$html$Html$Attributes$style, 'color', '#5B6572')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(f.ap)
								]))
						])) : A4(
					$author$project$Ui$inputField,
					'Email',
					f.ap,
					'email',
					function (v) {
						return $author$project$State$UpdateUserForm(
							function (g) {
								return _Utils_update(
									g,
									{ap: v});
							});
					}),
					A4(
					$author$project$Ui$selectField,
					'Role',
					$author$project$Types$roles,
					f.aX,
					function (v) {
						return $author$project$State$UpdateUserForm(
							function (g) {
								return _Utils_update(
									g,
									{aX: v});
							});
					}),
					pwField,
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('flex'),
							A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-primary'),
									$elm$html$Html$Events$onClick($author$project$State$SubmitUserForm)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Save')
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-outline'),
									$elm$html$Html$Events$onClick($author$project$State$CloseUserForm)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Cancel')
								]))
						]))
				])));
};
var $author$project$Main$workspaceHeading = function (model) {
	var section = function () {
		var _v2 = $author$project$State$routeOf(model.a_);
		switch (_v2.$) {
			case 0:
				return 'Overview';
			case 1:
				return 'Leads';
			case 2:
				return 'Lead details';
			case 3:
				return 'Clients';
			case 4:
				return 'Client details';
			case 5:
				return 'Tasks';
			case 6:
				return 'Team';
			case 7:
				return 'Audit history';
			default:
				var kind = _v2.a;
				return (kind === 'metrics') ? 'System' : _Utils_ap(
					$elm$core$String$toUpper(
						A2($elm$core$String$left, 1, kind)),
					A2($elm$core$String$dropLeft, 1, kind));
		}
	}();
	var _v0 = function () {
		var _v1 = $author$project$State$routeOf(model.a_);
		switch (_v1.$) {
			case 0:
				return _Utils_Tuple2('A clear view of what’s next.', 'Your relationships, progress and priorities in one place.');
			case 1:
				return _Utils_Tuple2('Build your next relationship.', 'Keep every conversation moving toward a clear next step.');
			case 3:
				return _Utils_Tuple2('Great service starts here.', 'A shared view of every client and their journey.');
			case 5:
				return _Utils_Tuple2('Make room for your best work.', 'Turn follow-ups and deadlines into progress.');
			case 6:
				return _Utils_Tuple2('Your people, connected.', 'Invite colleagues and manage their access.');
			case 7:
				return _Utils_Tuple2('Every change, accounted for.', 'A complete history of activity across your workspace.');
			default:
				return _Utils_Tuple2('Your client workspace.', 'Keep the details close and the next step clear.');
		}
	}();
	var title = _v0.a;
	var subtitle = _v0.b;
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('workspace-heading')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('workspace-topline')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('breadcrumb')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$a,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$href('/')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Workspace')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('/')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(section)
									]))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('workspace-date')
							]),
						_List_fromArray(
							[
								$author$project$Ui$icon('clock'),
								$elm$html$Html$text(model.cf)
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('heading-content')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('eyebrow')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('ECC / CLIENT OPERATIONS')
									])),
								A2(
								$elm$html$Html$h1,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(title)
									])),
								A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(subtitle)
									]))
							])),
						_Utils_eq(
						$author$project$State$routeOf(model.a_),
						$author$project$State$Dashboard) ? A2(
						$elm$html$Html$a,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('btn btn-primary heading-action'),
								$elm$html$Html$Attributes$href('/leads')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('View pipeline'),
								$author$project$Ui$icon('arrow')
							])) : A2($elm$html$Html$span, _List_Nil, _List_Nil)
					]))
			]));
};
var $author$project$Main$bodyView = function (model) {
	return (model.a_.A === '/portal') ? _List_fromArray(
		[
			$author$project$Features$portalView(model)
		]) : ((!model.L) ? _List_fromArray(
		[
			A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('login-wrap')
				]),
			_List_fromArray(
				[$author$project$Ui$spinner]))
		]) : (_Utils_eq(model.a$, $elm$core$Maybe$Nothing) ? _List_fromArray(
		[
			$author$project$Views$loginView(model)
		]) : $elm$core$List$concat(
		_List_fromArray(
			[
				_List_fromArray(
				[
					A2(
					$elm$html$Html$a,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$href('#main-content'),
							$elm$html$Html$Attributes$class('skip-link')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Skip to content')
						])),
					$author$project$Main$headerBar(model),
					A2(
					$elm$html$Html$main_,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('container'),
							$elm$html$Html$Attributes$id('main-content'),
							$elm$html$Html$Attributes$tabindex(-1)
						]),
					_List_fromArray(
						[
							$author$project$Main$workspaceHeading(model),
							(model.j !== '') ? A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('error-banner'),
									A2($elm$html$Html$Attributes$attribute, 'role', 'alert')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(model.j),
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('btn btn-sm btn-outline'),
											$elm$html$Html$Events$onClick(
											$author$project$State$NavigateTo(model.a_.A))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Try again')
										]))
								])) : A2($elm$html$Html$span, _List_Nil, _List_Nil),
							((model.j !== '') && (_Utils_eq(model.x, $elm$core$Maybe$Nothing) && _Utils_eq(model.cC, $elm$core$Maybe$Nothing))) ? A2($elm$html$Html$span, _List_Nil, _List_Nil) : $author$project$Main$pageView(model),
							$author$project$Main$pagination(model)
						]))
				]),
				model.af ? _List_fromArray(
				[
					$author$project$Views$userFormModal(model)
				]) : _List_Nil,
				model.aY ? _List_fromArray(
				[
					$author$project$Views$passwordModal(model)
				]) : _List_Nil,
				_List_fromArray(
				[
					$author$project$Features$conflictView(model)
				]),
				function () {
				var _v0 = model.an;
				if (!_v0.$) {
					var _v1 = _v0.a;
					var message = _v1.a;
					return _List_fromArray(
						[
							A2(
							$author$project$Ui$modal,
							'Confirm this action',
							A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$p,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(message)
											])),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('flex'),
												A2($elm$html$Html$Attributes$style, 'margin-top', '20px')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$button,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('btn btn-outline'),
														$elm$html$Html$Events$onClick($author$project$State$ConfirmDismissed)
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Cancel')
													])),
												A2(
												$elm$html$Html$button,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$class('btn btn-primary'),
														$elm$html$Html$Events$onClick($author$project$State$ConfirmAccepted)
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Confirm')
													]))
											]))
									])))
						]);
				} else {
					return _List_Nil;
				}
			}(),
				_List_fromArray(
				[
					$author$project$Views$toastStack(model)
				])
			]))));
};
var $author$project$Main$view = function (model) {
	return {
		aE: _List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class(
						model.ao ? 'app-root dark-mode' : 'app-root')
					]),
				$author$project$Main$bodyView(model))
			]),
		ay: 'ECC · Client workspace'
	};
};
var $author$project$Main$main = $elm$browser$Browser$application(
	{cY: $author$project$Main$init, c2: $author$project$State$UrlChanged, c3: $author$project$State$LinkClicked, dt: $author$project$Main$subscriptions, dy: $author$project$Main$update, dB: $author$project$Main$view});
_Platform_export({'Main':{'init':$author$project$Main$main(
	$elm$json$Json$Decode$succeed(0))(0)}});}(this));