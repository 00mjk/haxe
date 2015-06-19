class TestObjc extends haxe.unit.TestCase
{
	static function main()
	{
		var runner = new haxe.unit.TestRunner();
		runner.add(new TestObjc());
		var code = runner.run() ? 0 : 1;
		Sys.exit(code);
	}

	public function testCall()
	{
		var cls = TestClass.alloc().init();
		assertEquals(cls.getOtherThing(), 0);
		cls.setOtherThing(42);
		assertEquals(cls.getOtherThing(), 42);
		assertEquals(cls.isBiggerThan10(2), false);
		assertEquals(cls.isBiggerThan10(12), true);
		assertEquals(cls.isBiggerThan10Int(3), false);
		assertEquals(cls.isBiggerThan10Int(14), true);
		assertEquals(cls.addHello("World"), "Hello, World");
		cls.something = " test";
		assertEquals(cls.something, " test");
		assertEquals(cls.addSomething("Hey,"), "Hey, test");
		assertEquals(cls.addHelloAndString("World"," it works"), "Hello, World it works");
	}
}

@:include("./native/include/test.h")
@:sourceFile("./native/test.m")
@:objc extern class TestClass
{
	static function aStatic():Int;

	static function alloc():TestClass;
	function init():TestClass;

	var something(get,set):NSString;

	@:native("something") private function get_something():NSString;
	@:native("setSomething") private function set_something(value:NSString):NSString;

	function setOtherThing(value:Int):Void;
	function getOtherThing():Int;
	function getOtherThingChar():cpp.Int8;
	function addHello(str:NSString):NSString;
	@:native("addHello:andString") function addHelloAndString(str:NSString, str2:NSString):NSString;
	function addSomething(str:NSString):NSString;
	function isBiggerThan10(value:NSNumber):Bool;
	function isBiggerThan10Num(value:NSNumber):NSNumber;
	function isBiggerThan10Int(integer:Int):Bool;

	@:plain static function some_c_call(t:TestClass):Int;
	@:plain static function is_bigger_than_10(t:TestClass, val:Int):Bool;
}

@:forward abstract NSString(_NSString) from _NSString to _NSString
{
	@:from @:extern inline public static function fromString(str:String):NSString
		return _NSString.stringWithUTF8String(str);

	@:to @:extern inline public function toString():String
		return this.UTF8String();
}

@:native("NSString") @:objc extern class _NSString
{
	static function stringWithUTF8String(str:cpp.CastCharStar):NSString;

	function UTF8String():cpp.ConstCharStar;
}

@:forward abstract NSNumber(_NSNumber) from _NSNumber to _NSNumber
{
	@:from @:extern inline public static function fromInt(i:Int):NSNumber
		return _NSNumber.numberWithInt(i);

	@:to @:extern inline public function toInt():Int
		return this.intValue();
}

@:native("NSNumber") @:objc extern class _NSNumber
{
	static function numberWithInt(i:Int):NSNumber;
	function intValue():Int;
}
