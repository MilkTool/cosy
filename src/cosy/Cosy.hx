package cosy;

#if sys
import sys.io.File;
#end

class Cosy {
    static final interpreter = new Interpreter();

    static var hadError = false;
    static var hadRuntimeError = false;
    static var prettyPrint = false;
    static var javascript = false;
    static var testing = false;
    static var testOutput = '';

    static function main() {
        #if sys
        if (Sys.args().length == 0) {
            return runPrompt();
        }
        var argErrors = [];
        for (i in 0...Sys.args().length - 1) {
            var arg = Sys.args()[i];
            switch arg {
                case '--prettyprint': prettyPrint = true;
                case '--javascript': javascript = true;
                case _: argErrors.push(arg);
            }
        }
        
        if (argErrors.length > 0) {
            Sys.println('Unknown argument(s): ${argErrors.join(", ")}\n');
            Sys.println('Usage: hcosy (options) [script]\n\nOptions:\n --prettyprint\tPrints the formatted script\n --javascript\tPrints the corresponding JavaScript code');
            Sys.exit(64);
        }

        var file = Sys.args()[Sys.args().length - 1];
        if (!sys.FileSystem.exists(file)) {
            Sys.println('Source file not found: "$file"');
            Sys.exit(64);
        }

        runFile(file);
        #end
    }

    #if sys
    static function runFile(path:String) {
        var content = File.getContent(path);
        run(content);
        if (hadError) Sys.exit(65);
        if (hadRuntimeError) Sys.exit(70);
    }

    static function runPrompt() {
        var stdin = Sys.stdin();
        while (true) {
            Sys.print('> ');
            run(stdin.readLine());
        }
    }
    #end

    static public function test(source :String, prettyprint :Bool = false) :String {
        prettyPrint = prettyprint;
        testing = true;
        testOutput = '';
        run(source);
        testing = false;
        prettyPrint = false;
        return StringTools.trim(testOutput);
    }

    static public function println(v :Dynamic) {
        if (testing) {
            testOutput += v + '\n';
        } else {
            #if sys
            Sys.println(v);
            #elseif js
            js.Browser.console.log(v);
            #end
        }
    }

    @:expose // TODO: Maybe expose shallow?
    static function validate(source:String) {
        hadError = false;

        var scanner = new Scanner(source);
        var tokens = scanner.scanTokens();
        var parser = new Parser(tokens);
        var statements = parser.parse();

        if (hadError) return;

        var resolver = new Resolver(interpreter);
        resolver.resolve(statements);

        var typer = new Typer();
        typer.type(statements);

        if (hadError) return;
    }

    @:expose
    static function run(source:String) {
        hadError = false;

        var scanner = new Scanner(source);
        var tokens = scanner.scanTokens();
        var parser = new Parser(tokens);
        var statements = parser.parse();

        if (hadError) return;

        var resolver = new Resolver(interpreter);
        resolver.resolve(statements);

        var typer = new Typer();
        typer.type(statements);

        if (hadError) return;

        var optimizer = new Optimizer();
        statements = optimizer.optimize(statements);

        if (prettyPrint) {
            var printer = new AstPrinter();
            for (stmt in statements) println(printer.printStmt(stmt));
            return;
        }

        if (javascript) {
            // Hack to inject a JavaScript standard library
            var stdLib = '// standard library\nlet clock = Date.now;\n';
            println(stdLib);

            var printer = new JavaScriptPrinter();
            for (stmt in statements) println(printer.printStmt(stmt));
            return;
        }

        interpreter.interpret(statements);
    }

    static function reportWarning(line:Int, where:String, message:String) {
        println('[line $line] Warning $where: $message');
    }

    public static function warning(data:ErrorData, message:String) {
        switch data {
            case Line(line): reportWarning(line, '', message);
            case Token(token) if (token.type == Eof): reportWarning(token.line, 'at end', message);
            case Token(token): reportWarning(token.line, 'at "${token.lexeme}"', message);
        }
    }

    static function report(line:Int, where:String, message:String) {
        // println('\033[1;31m[line $line] Error $where: $message\033[0m');
        println('[line $line] Error $where: $message');
        hadError = true;
    }

    public static function error(data:ErrorData, message:String) {
        switch data {
            case Line(line): report(line, '', message);
            case Token(token) if (token.type == Eof): report(token.line, 'at end', message);
            case Token(token): report(token.line, 'at "${token.lexeme}"', message);
        }
    }

    public static function runtimeError(e:RuntimeError) {
        println('[line ${e.token.line}] Runtime Error: ${e.message}');
        hadRuntimeError = true;
    }
}

enum ErrorDataType {
    Line(v:Int);
    Token(v:Token);
}

abstract ErrorData(ErrorDataType) from ErrorDataType to ErrorDataType {
    @:from static inline function line(v:Int):ErrorData return Line(v);
    @:from static inline function token(v:Token):ErrorData return Token(v);
}