#include "structures.hpp"
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
		<< std::make_pair("arrayPointer", value.arrayPointer) << c
		<< std::make_pair("baseName", value.baseName) << c
		<< std::make_pair("fullName", value.fullName) << c;
	if (!value.desugared.empty()) {
		s << std::make_pair("desugared", value.desugared) << c;
	}
	if (!value.typedefs.empty()) {
		s << std::make_pair("typedefs", value.typedefs) << c;
	}
	s << std::make_pair("template", value.templ);
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

void LiteralData::clear() { this->kind = None; }
void LiteralData::set(bool v) { this->kind = BoolKind; this->container.bool_value = v; }
void LiteralData::set(int64_t v) { this->kind = IntKind; this->container.int_value = v; }
void LiteralData::set(uint64_t v) { this->kind = UIntKind; this->container.uint_value = v; }
void LiteralData::set(double v) { this->kind = DoubleKind; this->container.double_value = v; }
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
	case LiteralData::StringKind:
		s << *value.container.string_value;
		break;
	default:
		s << JsonStream::Null;
	}
	return s;
}

// Writes the documentation comment *doc*, or `null` if there's none.
static JsonStream &writeDoc(JsonStream &s, const std::string &doc) {
	if (doc.empty())
		return s << std::make_pair("doc", JsonStream::Null);
	else
		return s << std::make_pair("doc", doc);
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
		case Method::ConversionOperator: return s << "ConversionOperator";
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
		<< std::make_pair("isBuiltin", value.isBuiltin) << c
		<< std::make_pair("isConst", value.isConst) << c
		<< std::make_pair("isVirtual", value.isVirtual) << c
		<< std::make_pair("isPure", value.isPure) << c
		<< std::make_pair("isFinal", value.isFinal) << c
		<< std::make_pair("isExternC", value.isExternC) << c
		<< std::make_pair("isDeprecated", value.isDeprecated) << c
		<< std::make_pair("className", value.className) << c;

	if (value.firstDefaultArgument < 0) {
		s << std::make_pair("firstDefaultArgument", JsonStream::Null) << c;
	} else {
		s << std::make_pair("firstDefaultArgument", value.firstDefaultArgument) << c;
	}

	s << std::make_pair("arguments", value.arguments) << c
	  << std::make_pair("returnType", value.returnType) << c;
	writeDoc(s, value.doc);

	return s << JsonStream::ObjectEnd;
}

JsonStream &operator<<(JsonStream &s, clang::AccessSpecifier value) {
	switch (value) {
		case clang::AS_public: return s << "Public";
		case clang::AS_protected: return s << "Protected";
		case clang::AS_private: return s << "Private";
		default: return s << "BUG IN Bindgen";
	}
}

JsonStream &operator<<(JsonStream &s, const BaseClass &value) {
	auto c = JsonStream::Comma;
	return s
		<< JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("isVirtual", value.isVirtual) << c
		<< std::make_pair("inheritedConstructor", value.inheritedConstructor) << c
		<< std::make_pair("access", value.access) << c
		<< std::make_pair("offset", value.offset)
		<< JsonStream::ObjectEnd;
}

JsonStream &operator<<(JsonStream &s, const Field &value) {
	auto c = JsonStream::Comma;
	s << JsonStream::ObjectBegin;
	writeTypeJson(s, value) << c;
	s << std::make_pair("name", value.name) << c
		<< std::make_pair("access", value.access) << c
		<< std::make_pair("isStatic", value.isStatic) << c
		<< std::make_pair("hasDefault", value.hasDefault) << c;

	if (value.hasDefault && value.value.hasValue()) {
		s << std::make_pair("value", value.value) << c;
	}

	if (value.bitField >= 0)
		s << std::make_pair("bitField", value.bitField) << c;
	else
		s << std::make_pair("bitField", JsonStream::Null) << c;

	if (value.bitOffset >= 0) {
		s << std::make_pair("bitOffset", value.bitOffset) << c
		  << std::make_pair("bitSize", value.bitSize) << c;
	} else {
		s << std::make_pair("bitOffset", JsonStream::Null) << c
		  << std::make_pair("bitSize", JsonStream::Null) << c;
	}

	writeDoc(s, value.doc);
	return s << JsonStream::ObjectEnd;
}

// `TagTypeKind` became a scoped enum in Clang 18.
#if CLANG_VERSION_MAJOR >= 18
#  define BG_TAG_KIND(kind) clang::TagTypeKind::kind
#else
#  define BG_TAG_KIND(kind) clang::TTK_##kind
#endif

JsonStream &operator<<(JsonStream &s, clang::TagTypeKind value) {
	switch (value) {
		case BG_TAG_KIND(Class): return s << "Class";
		case BG_TAG_KIND(Struct): return s << "Struct";
		case BG_TAG_KIND(Union): return s << "CppUnion"; // avoid confusion with Crystal union
		case BG_TAG_KIND(Interface): return s << "Interface";
		case BG_TAG_KIND(Enum): return s << "Enum";
		default: return s << "BUG IN Bindgen";
	}
}

JsonStream &operator<<(JsonStream &s, const Class &value) {
	auto c = JsonStream::Comma;
	s
		<< JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("byteSize", value.byteSize) << c
		<< std::make_pair("packAlignment", value.packAlignment) << c
		<< std::make_pair("typeKind", value.typeKind) << c
		<< std::make_pair("isAbstract", value.isAbstract) << c
		<< std::make_pair("isFinal", value.isFinal) << c
		<< std::make_pair("isPolymorphic", value.isPolymorphic) << c
		<< std::make_pair("isTriviallyCopyable", value.isTriviallyCopyable) << c
		<< std::make_pair("isStandardLayout", value.isStandardLayout) << c
		<< std::make_pair("isAnonymous", value.isAnonymous) << c
		<< std::make_pair("isDestructible", value.isDestructible) << c
		<< std::make_pair("hasDefaultConstructor", value.hasDefaultConstructor) << c
		<< std::make_pair("hasCopyConstructor", value.hasCopyConstructor) << c
		<< std::make_pair("hasUserDeclaredConstructor", value.hasUserDeclaredConstructor) << c
		<< std::make_pair("bases", value.bases) << c
		<< std::make_pair("fields", value.fields) << c
		<< std::make_pair("methods", value.methods) << c;
	writeDoc(s, value.doc);

	return s << JsonStream::ObjectEnd;
}

JsonStream &operator<<(JsonStream &s, const Enum &value) {
	auto c = JsonStream::Comma;
	s
		<< JsonStream::ObjectBegin
		<< std::make_pair("name", value.name) << c
		<< std::make_pair("type", value.type) << c
		<< std::make_pair("isFlags", value.isFlags) << c
		<< std::make_pair("isAnonymous", value.isAnonymous) << c
		<< std::make_pair("values", value.values) << c;
	writeDoc(s, value.doc);

	return s << JsonStream::ObjectEnd;
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
		<< std::make_pair("version", BG_FORMAT_VERSION) << c
		<< std::make_pair("enums", value.enums) << c
		<< std::make_pair("classes", value.classes) << c
		<< std::make_pair("functions", value.functions) << c
		<< std::make_pair("macros", value.macros)
		<< JsonStream::ObjectEnd;
}
