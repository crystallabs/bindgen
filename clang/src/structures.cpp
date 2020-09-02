#include "structures.hpp"
#include "helper.hpp"
#include "json_stream.hpp"

static JsonStream &writeTypeJson(JsonStream &s, const Type &value) {
	auto c = JsonStream::Comma;
	s << std::make_pair("isConst", value.isConst) << c
		<< std::make_pair("isMove", value.isMove) << c
		<< std::make_pair("isReference", value.isReference) << c
		<< std::make_pair("isBuiltin", value.isBuiltin) << c
		<< std::make_pair("isVoid", value.isVoid) << c
		<< std::make_pair("pointer", value.pointer) << c
		<< std::make_pair("extents", value.extents) << c
		<< std::make_pair("baseName", value.baseName) << c
		<< std::make_pair("fullName", value.fullName) << c
		<< std::make_pair("template", value.templ);
	return s;
}

JsonStream &operator<<(JsonStream &s, const Type &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin;
	writeTypeJson(s, value);
	s << JsonStream::ObjectEnd;
	return s;
}

JsonStream &operator<<(JsonStream &s, const Template &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin
	  << std::make_pair("baseName", value.baseName) << c
	  << std::make_pair("fullName", value.fullName) << c
	  << std::make_pair("arguments", value.arguments)
	 	<< JsonStream::ObjectEnd;
	return s;
}

LiteralData::LiteralData() : kind(None) { }
LiteralData::LiteralData(const LiteralData &other)
		: kind(other.kind), container(other.container)
{
	if (kind == StringKind)
		this->container.string_value = new std::string(*other.container.string_value);
}

LiteralData::~LiteralData() {
	if (kind == StringKind)
		delete this->container.string_value;
}

bool LiteralData::hasValue() const {
	return (this->kind != None);
}

void LiteralData::set(bool v) { this->kind = BoolKind; this->container.bool_value = v; }
void LiteralData::set(int64_t v) { this->kind = IntKind; this->container.int_value = v; }
void LiteralData::set(uint64_t v) { this->kind = UIntKind; this->container.uint_value = v; }
void LiteralData::set(double v) { this->kind = DoubleKind; this->container.double_value = v; }
void LiteralData::set(JsonStream::Terminal v) { this->kind = TerminalKind; this->container.terminal_value = v; }
void LiteralData::set(const std::string &v) {
	this->kind = StringKind;
	this->container.string_value = new std::string(v);
}

JsonStream &operator<<(JsonStream &s, const LiteralData &value) {
	// This will be much better with C++17 std::variant :)
	switch(value.kind) {
	case LiteralData::BoolKind:
		s << value.container.bool_value;
		break;
	case LiteralData::IntKind:
		s << value.container.int_value;
		break;
	case LiteralData::UIntKind:
		s << value.container.uint_value;
		break;
	case LiteralData::DoubleKind:
		s << value.container.double_value;
		break;
	case LiteralData::TerminalKind:
		s << value.container.terminal_value;
		break;
	case LiteralData::StringKind:
		s << *value.container.string_value;
		break;
	default:
		s << JsonStream::Null;
	}
	return s;
}

JsonStream &operator<<(JsonStream &s, const Argument &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin;
	writeTypeJson(s, value) << c;
	s << std::make_pair("hasDefault", value.hasDefault) << c
	  << std::make_pair("isVariadic", value.isVariadic) << c
	  << std::make_pair("name", value.name);

	if (value.hasDefault && value.value.hasValue()) {
		s << c << std::make_pair("value", value.value);
	}

	s << JsonStream::ObjectEnd;
	return s;
}

JsonStream &operator<<(JsonStream &s, Method::MethodType value) {
	switch (value) {
		case Method::Constructor: return s << "Constructor";
		case Method::CopyConstructor: return s << "CopyConstructor";
		case Method::MemberMethod: return s << "MemberMethod";
		case Method::StaticMethod: return s << "StaticMethod";
		case Method::Operator: return s << "Operator";
		case Method::Signal: return s << "Signal";
		default: return s << "BUG IN BINDGEN";
	}
}

JsonStream &operator<<(JsonStream &s, const Method &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin
		<< std::make_pair("type", value.type) << c
		<< std::make_pair("access", value.access) << c
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("isConst", value.isConst) << c
		<< std::make_pair("isVirtual", value.isVirtual) << c
		<< std::make_pair("isPure", value.isPure) << c
		<< std::make_pair("isExternC", value.isExternC) << c
		<< std::make_pair("className", value.className) << c;

	if (value.firstDefaultArgument < 0) {
		s << std::make_pair("firstDefaultArgument", JsonStream::Null) << c;
	} else {
		s << std::make_pair("firstDefaultArgument", value.firstDefaultArgument) << c;
	}

	s << std::make_pair("arguments", value.arguments) << c
	  << std::make_pair("returnType", value.returnType)
		<< JsonStream::ObjectEnd;

	return s;
}

JsonStream &operator<<(JsonStream &s, clang::AccessSpecifier value) {
	switch (value) {
		case clang::AS_public: return s << "Public";
		case clang::AS_protected: return s << "Protected";
		case clang::AS_private: return s << "Private";
		case clang::AS_none: return s << "BUG IN Bindgen";
	}
}

JsonStream &operator<<(JsonStream &s, const BaseClass &value) {
	auto c = JsonStream::Comma;
	return s
		<< JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("isVirtual", value.isVirtual) << c
		<< std::make_pair("inheritedConstructor", value.inheritedConstructor) << c
		<< std::make_pair("access", value.access)
		<< JsonStream::ObjectEnd;
}

JsonStream &operator<<(JsonStream &s, const Field &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin;
	writeTypeJson(s, value) << c;
	s << std::make_pair("name", value.name) << c
		<< std::make_pair("access", value.access) << c;

	if (value.bitField > 0)
		s << std::make_pair("bitField", value.name);
	else
		s << std::make_pair("bitField", JsonStream::Null);

	return s << JsonStream::ObjectEnd;
}

JsonStream &operator<<(JsonStream &s, const Class &value) {
	auto c = JsonStream::Comma;
	return s
		<< JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("byteSize", value.byteSize) << c
		<< std::make_pair("isClass", value.isClass) << c
		<< std::make_pair("isAbstract", value.isAbstract) << c
		<< std::make_pair("isDestructible", value.isDestructible) << c
		<< std::make_pair("hasDefaultConstructor", value.hasDefaultConstructor) << c
		<< std::make_pair("hasCopyConstructor", value.hasCopyConstructor) << c
		<< std::make_pair("bases", value.bases) << c
		<< std::make_pair("fields", value.fields) << c
		<< std::make_pair("methods", value.methods)
		<< JsonStream::ObjectEnd;
}

JsonStream &operator<<(JsonStream &s, const Enum &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("type", value.type) << c
		<< std::make_pair("isFlags", value.isFlags) << c
		<< "values" << JsonStream::Separator << JsonStream::ObjectBegin;

	bool first = true;
	for (const std::pair<std::string, int64_t> &elem : value.values) {
		if (!first) s << c;
		s << std::make_pair(elem.first, elem.second);
		first = false;
	}

	s << JsonStream::ObjectEnd << JsonStream::ObjectEnd;
	return s;
}

JsonStream &operator<<(JsonStream &s, const Macro &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("isFunction", value.isFunction) << c
		<< std::make_pair("isVarArg", value.isVarArg) << c
		<< std::make_pair("arguments", value.arguments) << c
		<< std::make_pair("value", value.value);

	if (value.type) {
		s << c
		  << std::make_pair("type", *value.type) << c
		  << std::make_pair("evaluated", value.evaluated);
	}

	s << JsonStream::ObjectEnd;
	return s;
}

JsonStream &operator<<(JsonStream &s, const Document &value) {
	auto c = JsonStream::Comma;
	return s
		<< JsonStream::ObjectBegin
		<< std::make_pair("enums", value.enums) << c
		<< std::make_pair("classes", value.classes) << c
		<< std::make_pair("functions", value.functions) << c
		<< std::make_pair("macros", value.macros)
		<< JsonStream::ObjectEnd;
}
