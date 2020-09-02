#ifndef STRUCTURES_HPP
#define STRUCTURES_HPP

#include "helper.hpp"
#include "json_stream.hpp"
#include "clang/AST/DeclCXX.h"

// Forward declare for `Type::templ`
struct Template;

struct Type {
	bool isConst = false; // Constant?
	bool isMove = false; // Move semantics?
	int pointer = 0; // Pointer depth
	bool isReference = false; // If this is a reference
	bool isBuiltin = false; // If this is a C++ built-in type.
	bool isVoid = false; // If the derefenced type is C++ `void`.
	std::vector<uint64_t> extents; // C array extents, e.g. `int[][5][3]` => `{0, 5, 3}`
	std::string baseName; // Base type. E.g., `const Foo *&` => `Foo`
	std::string fullName; // Full name, for C++. E.g. `const Foo *&`

	CopyPtr<Template> templ = nullptr;
};

JsonStream &operator<<(JsonStream &s, const Type &value);

struct Template {
	std::string fullName; // The template class, e.g. `std::vector<_Tp, _Alloc>` in `std::vector<std::string>`
	std::string baseName; // The template class-name, e.g. `std::vector`
	std::vector<Type> arguments; // Arguments, e.g. `std::string`
};

JsonStream &operator<<(JsonStream &s, const Template &value);

struct LiteralData {
	enum Kind {
		None,
		BoolKind,
		IntKind,
		UIntKind,
		DoubleKind,
		StringKind,
		TerminalKind,
	};

	Kind kind;

	union {
		bool bool_value;
		int64_t int_value;
		uint64_t uint_value;
		double double_value;
		JsonStream::Terminal terminal_value;
		std::string *string_value;
	} container;

	LiteralData();
	LiteralData(const LiteralData &other);

	~LiteralData();

	bool hasValue() const;

	template<typename T>
	LiteralData &operator=(const T &value) {
		set(value);
		return *this;
	}

	// Setters

	void set(bool v);
	void set(int64_t v);
	void set(uint64_t v);
	void set(double v);
	void set(JsonStream::Terminal v);
	void set(const std::string &v);
};

JsonStream &operator<<(JsonStream &s, const LiteralData &value);

struct Argument : public Type {
	bool isVariadic; // Is this argument the `...` vararg?
	bool hasDefault; // Does this argument have a default value?
	std::string name; // Name of the argument

	// Use this once C++17 compilers are widely used.
	// std::variant< bool, int64_t, uint64_t, double, JsonStream::Terminal > value;
	LiteralData value;
};

JsonStream &operator<<(JsonStream &s, const Argument &value);

struct Method {
	enum MethodType {
		Unknown, // Not exposed!
		Constructor,
		CopyConstructor,
		// Destructor,
		MemberMethod,
		// MemberGetter,
		// MemberSetter,
		StaticMethod,
		Operator, // Overloaded operator
		Signal, // Qt signal
	};

	MethodType type = Unknown; // Method type
	std::string name; // Name of the method.  Empty for de-/constructors.
	clang::AccessSpecifier access; // Access level
	bool isConst = false; // Is this method const qualified?
	bool isVirtual = false; // Is this method virtual?
	bool isPure = false; // Pure virtual?
	bool isExternC = false; // Does the function use C ABI?
	std::string className; // Name of the class.
	std::vector<Argument> arguments; // Arguments
	int firstDefaultArgument = -1;
	Type returnType; // Return type.  Not filled for a constructor.
};

JsonStream &operator<<(JsonStream &s, Method::MethodType value);

JsonStream &operator<<(JsonStream &s, const Method &value);

struct BaseClass {
	bool isVirtual; // Is this a virtual inheritance?
	bool inheritedConstructor; // Do we inherit a constructor from this class?
	std::string name; // Name of the class
	clang::AccessSpecifier access; // Access level
};

JsonStream &operator<<(JsonStream &s, clang::AccessSpecifier value);

JsonStream &operator<<(JsonStream &s, const BaseClass &value);

struct Field : public Type {
	clang::AccessSpecifier access;
	std::string name;
	int bitField = -1;
};

JsonStream &operator<<(JsonStream &s, const Field &value);

struct Class {
	bool isClass; // Class or struct?
	bool hasDefaultConstructor;
	bool hasCopyConstructor;
	bool isDestructible = true; // Does this class have a public or protected destructor?
	bool isAbstract; // Does the class have pure virtual methods?
	int byteSize; // Size of an instance in memory.
	std::string name; // Fully::qualified::class::name
	std::vector<BaseClass> bases; // Names of base classes
	std::vector<Method> methods; // Methods
	std::vector<Field> fields; // Accessible fields
};

JsonStream &operator<<(JsonStream &s, const Class &value);

struct Enum {
	std::string name;
	std::string type;
	bool isFlags = false;
	std::vector<std::pair<std::string, int64_t>> values;
};

JsonStream &operator<<(JsonStream &s, const Enum &value);

struct Macro {
	std::string name; // Name of the macro
	bool isFunction; // Is this macro function like?
	std::vector<std::string> arguments; // Arguments for a function-like macro
	bool isVarArg; // Does it end in a variable argument list?
	std::string value; // The unparsed macro body
	LiteralData evaluated; // The evaluated macro value
	CopyPtr<Type> type; // The type of the evaluated macro value
};

JsonStream &operator<<(JsonStream &s, const Macro &value);

struct Document {
	std::map<std::string, Enum> enums;
	std::map<std::string, Class> classes;
	std::vector<Method> functions;
	std::vector<Macro> macros;
};

JsonStream &operator<<(JsonStream &s, const Document &value);

#endif // STRUCTURES_HPP
