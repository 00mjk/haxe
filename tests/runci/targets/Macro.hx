package runci.targets;

import sys.FileSystem;
import runci.System.*;
import runci.Config.*;

class Macro {
	static public function run(args:Array<String>) {
		runCommand("haxe", ["compile-macro.hxml"].concat(args));

		changeDirectory(displayDir);
		haxelibInstallGit("Simn", "haxeserver");
		runCommand("haxe", ["build.hxml"]);

		changeDirectory(sourcemapsDir);
		runCommand("haxe", ["run.hxml"]);

		changeDirectory(nullSafetyDir);
		infoMsg("No-target null safety:");
		runCommand("haxe", ["test.hxml"]);
		infoMsg("Js-es6 null safety:");
		runCommand("haxe", ["test-js-es6.hxml"]);

		changeDirectory(miscDir);
		runCommand("haxe", ["compile.hxml"]);

		changeDirectory(sysDir);
		runCommand("haxe", ["compile-macro.hxml"].concat(args));

		changeDirectory(asysDir);
		runCommand("haxe", ["build-eval.hxml"]);

		switch Sys.systemName() {
			case 'Linux':
				changeDirectory(miscDir + 'compiler_loops');
				runCommand("haxe", ["run.hxml"]);
			case _: // TODO
		}

		runci.targets.Java.getJavaDependencies(); // this is awkward
		haxelibInstallGit("Simn", "haxeserver", "asys");
		changeDirectory(serverDir);
		runCommand("haxe", ["build.hxml"]);

		// changeDirectory(threadsDir);
		// runCommand("haxe", ["build.hxml", "--interp"]);
	}
}