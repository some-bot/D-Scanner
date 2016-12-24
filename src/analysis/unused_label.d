// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.unused_label;

import dparse.ast;
import dparse.lexer;
import analysis.base;
import analysis.helpers;
import dsymbol.scope_ : Scope;

class UnusedLabelCheck : BaseAnalyzer
{
	alias visit = BaseAnalyzer.visit;

	this(string fileName, const(Scope)* sc, bool skipTests = false)
	{
		super(fileName, sc, skipTests);
	}

	override void visit(const Module mod)
	{
		pushScope();
		mod.accept(this);
		popScope();
	}

	override void visit(const FunctionBody functionBody)
	{
		if (functionBody.blockStatement !is null)
		{
			pushScope();
			functionBody.blockStatement.accept(this);
			popScope();
		}
		if (functionBody.bodyStatement !is null)
		{
			pushScope();
			functionBody.bodyStatement.accept(this);
			popScope();
		}
		if (functionBody.outStatement !is null)
		{
			pushScope();
			functionBody.outStatement.accept(this);
			popScope();
		}
		if (functionBody.inStatement !is null)
		{
			pushScope();
			functionBody.inStatement.accept(this);
			popScope();
		}
	}

	override void visit(const LabeledStatement labeledStatement)
	{
		auto token = &labeledStatement.identifier;
		Label* label = token.text in current;
		if (label is null)
		{
			current[token.text] = Label(token.text, token.line, token.column, false);
		}
		else
		{
			label.line = token.line;
			label.column = token.column;
		}
		if (labeledStatement.declarationOrStatement !is null)
			labeledStatement.declarationOrStatement.accept(this);
	}

	override void visit(const ContinueStatement contStatement)
	{
		if (contStatement.label.text.length)
			labelUsed(contStatement.label.text);
	}

	override void visit(const BreakStatement breakStatement)
	{
		if (breakStatement.label.text.length)
			labelUsed(breakStatement.label.text);
	}

	override void visit(const GotoStatement gotoStatement)
	{
		if (gotoStatement.label.text.length)
			labelUsed(gotoStatement.label.text);
	}

	override void visit(const AsmInstruction instr)
	{
		instr.accept(this);

		bool jmp;
		if (instr.identifierOrIntegerOrOpcode.text.length)
			jmp = instr.identifierOrIntegerOrOpcode.text[0] == 'j';

		if (!jmp || instr.operands.operands.length != 1)
			return;

		const AsmExp e = cast(AsmExp) instr.operands.operands[0];
		if (e.left && cast(const(AsmBrExp)) e.left)
		{
			const AsmBrExp b = cast(AsmBrExp) e.left;
			if (b.asmUnaExp && b.asmUnaExp.asmPrimaryExp)
			{
				const AsmPrimaryExp p = b.asmUnaExp.asmPrimaryExp;
				if (p && p.identifierChain && p.identifierChain.identifiers.length == 1)
					labelUsed(p.identifierChain.identifiers[0].text);
			}
		}
	}

private:

	static struct Label
	{
		string name;
		size_t line;
		size_t column;
		bool used;
	}

	Label[string][] stack;

	auto ref current() @property
	{
		return stack[$ - 1];
	}

	void pushScope()
	{
		stack.length++;
	}

	void popScope()
	{
		foreach (label; current.byValue())
		{
			assert(label.line != size_t.max && label.column != size_t.max);
			if (!label.used)
			{
				addErrorMessage(label.line, label.column, "dscanner.suspicious.unused_label",
						"Label \"" ~ label.name ~ "\" is not used.");
			}
		}
		stack.length--;
	}

	void labelUsed(string name)
	{
		Label* entry = name in current;
		if (entry is null)
			current[name] = Label(name, size_t.max, size_t.max, true);
		else
			entry.used = true;
	}
}

unittest
{
	import analysis.config : StaticAnalysisConfig, Check;
	import std.stdio : stderr;

	StaticAnalysisConfig sac;
	sac.unused_label_check = Check.enabled;
	assertAnalyzerWarnings(q{
		int testUnusedLabel()
		{
		    int x = 0;
		A: // [warn]: Label "A" is not used.
			if (x) goto B;
			x++;
		B:
			goto C;
			void foo()
			{
			C: // [warn]: Label "C" is not used.
				return;
			}
		C:
			void bar()
			{
				goto D;
			D:
				return;
			}
		D: // [warn]: Label "D" is not used.
			goto E;
			() {
			E: // [warn]: Label "E" is not used.
				return;
			}();
		E:
			() {
				goto F;
			F:
				return;
			}();
		F: // [warn]: Label "F" is not used.
			return x;
		G: // [warn]: Label "G" is not used.
		}
	}c, sac);

	assertAnalyzerWarnings(q{
		void testAsm()
		{
			asm { jmp lbl;}
			lbl:
		}
	}c, sac);

	assertAnalyzerWarnings(q{
		void testAsm()
		{
			asm { mov RAX,1;}
			lbl: // [warn]: Label "lbl" is not used.
		}
	}c, sac);

	stderr.writeln("Unittest for UnusedLabelCheck passed.");
}
