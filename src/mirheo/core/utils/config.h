#pragma once

#include "common.h" // Forward declarations of Config and ConfigDumper<>.
#include "flat_ordered_dict.h"
#include "reflection.h"
#include "type_traits.h"

#include <cassert>
#include <map>
#include <mpi.h>
#include <string>
#include <vector>

#include <extern/variant/include/mpark/variant.hpp>
#include <vector_types.h>

namespace mirheo
{

class Dumper;
class Undumper;

template <typename T, typename Enable>
struct ConfigDumper
{
    static_assert(std::is_same<remove_cvref_t<T>, T>::value,
                  "Type must be a non-const non-reference type.");
    static_assert(always_false<T>::value, "Not implemented.");

    static Config dump(Dumper&, T& value);
    static T undump(Undumper&, const Config &);
};

class ConfigDictionary : public FlatOrderedDict<std::string, Config>
{
    using Base = FlatOrderedDict<std::string, Config>;

public:
    using Base::Base;
};

class Config
{
public:
    using Int        = long long;
    using Float      = double;
    using String     = std::string;
    using List       = std::vector<Config>;
    using Dictionary = ConfigDictionary;
    using Variant    = mpark::variant<Int, Float, String, List, Dictionary>;

    Config(Int value) : value_{value} {}
    Config(Float value) : value_{value} {}
    Config(String value) : value_{std::move(value)} {}
    Config(Dictionary value) : value_{std::move(value)} {}
    Config(List value) : value_{std::move(value)} {}
    Config(const char *str) : value_{std::string(str)} {}
    Config(const Config&) = default;
    Config(Config&&)      = default;
    Config& operator=(const Config&) = default;
    Config& operator=(Config&&) = default;

    template <typename T>
    Config(const T&)
    {
        static_assert(
            always_false<T>::value,
            "Direct construction of the Config object available only "
            "for variant types (Int, Float, String, Dictionary, List). "
            "Did you mean `dumper(value)` instead of `Config{value}`?");
    }

    std::string toJSONString() const;

    /// Getter functions. Terminate if the underlying type is different. Int
    /// and Float variants accept the other type if the conversion is lossless.
    Int getInt() const;
    Float getFloat() const;
    const String& getString() const;
    const List& getList() const;
    List& getList();
    const Dictionary& getDict() const;
    Dictionary& getDict();

    /// Get the element matching the given key. Terminates if not a dict, or if
    /// the key was not found.
    Config& at(const std::string &key);
    Config& at(const char *key);
    const Config& at(const std::string &key) const;
    const Config& at(const char *key) const;

    /// Get the list element. Terminates if not a list or if out of range.
    Config& at(size_t i);
    const Config& at(size_t i) const;

    Config& at(int i) { return at(static_cast<size_t>(i)); }
    const Config& at(int i) const { return at(static_cast<size_t>(i)); }

    template <typename T>
    inline const T& get() const
    {
        return mpark::get<T>(value_);
    }
    template <typename T>
    inline const T* get_if() const noexcept
    {
        return mpark::get_if<T>(&value_);
    }
    template <typename T>
    inline T* get_if() noexcept
    {
        return mpark::get_if<T>(&value_);
    }

    size_t index() const noexcept { return value_.index(); }

private:
    Variant value_;
};

struct DumpContext
{
    std::string path {"snapshot/"};
    MPI_Comm groupComm {MPI_COMM_NULL};
    std::map<std::string, int> counters;

    bool isGroupMasterTask() const;
};

struct UndumpContext
{
    std::string path {"snapshot/"};
    MPI_Comm groupComm {MPI_COMM_NULL};
};

class Dumper
{
public:
    Dumper(DumpContext context);
    ~Dumper();

    DumpContext& getContext() noexcept { return context_; }
    const Config& getConfig() const noexcept { return config_; }

    /// Dump.
    template <typename T>
    Config operator()(T& t)
    {
        return ConfigDumper<std::remove_const_t<T>>::dump(*this, t);
    }
    template <typename T>
    Config operator()(const T& t)
    {
        return ConfigDumper<T>::dump(*this, t);
    }
    template <typename T>
    Config operator()(T* t)
    {
        return ConfigDumper<std::remove_const_t<T>*>::dump(*this, t);
    }
    Config operator()(const char* t)
    {
        return std::string(t);
    }

    bool isObjectRegistered(const void*) const noexcept;
    const std::string& getObjectDescription(const void*) const;
    const std::string& registerObject(const void*, Config newItem);

private:
    Config config_;
    std::map<const void*, std::string> descriptions_;
    DumpContext context_;
};

class Undumper
{
public:
    Undumper(UndumpContext context);
    ~Undumper();

    UndumpContext& getContext() noexcept { return context_; }

    template <typename T>
    T undump(const Config &config)
    {
        return ConfigDumper<T>::undump(*this, config);
    }

private:
    UndumpContext context_;
};

namespace detail
{
    struct DumpHandler
    {
        template <typename... Args>
        void process(Args&& ...items)
        {
            dict_->reserve(dict_->size() + sizeof...(items));

            // https://stackoverflow.com/a/51006031
            // Note: initializer list preserves the order of evaluation!
            using fold_expression = int[];
            (void)fold_expression{0, (dict_->insert(std::forward<Args>(items)), 0)...};
        }

        template <typename T>
        Config::Dictionary::value_type operator()(std::string name, T *t) const
        {
            return {std::move(name), (*dumper_)(*t)};
        }

        Config::Dictionary *dict_;
        Dumper *dumper_;
    };
} // namespace detail

#define MIRHEO_DUMPER_PRIMITIVE(TYPE, ELTYPE)                                  \
    template <>                                                                \
    struct ConfigDumper<TYPE>                                                  \
    {                                                                          \
        static Config dump(Dumper&, TYPE x)                                    \
        {                                                                      \
            return static_cast<Config::ELTYPE>(x);                             \
        }                                                                      \
        static TYPE undump(Undumper&, const Config &value)                     \
        {                                                                      \
            return static_cast<TYPE>(value.get##ELTYPE());                     \
        }                                                                      \
    }
MIRHEO_DUMPER_PRIMITIVE(bool,               Int);
MIRHEO_DUMPER_PRIMITIVE(int,                Int);
MIRHEO_DUMPER_PRIMITIVE(long,               Int);
MIRHEO_DUMPER_PRIMITIVE(long long,          Int);
MIRHEO_DUMPER_PRIMITIVE(unsigned,           Int);
MIRHEO_DUMPER_PRIMITIVE(unsigned long,      Int);  // This is risky.
MIRHEO_DUMPER_PRIMITIVE(unsigned long long, Int);  // This is risky.
MIRHEO_DUMPER_PRIMITIVE(float,              Float);
MIRHEO_DUMPER_PRIMITIVE(double,             Float);
#undef MIRHEO_DUMPER_PRIMITIVE

template <>
struct ConfigDumper<const char*>
{
    static Config dump(Dumper&, const char *str)
    {
        return std::string(str);
    }
    static const char* undump(Undumper&, const Config&) = delete;
};

template <>
struct ConfigDumper<std::string>
{
    static Config dump(Dumper&, std::string x)
    {
        return std::move(x);
    }
    static const std::string& undump(Undumper&, const Config &config)
    {
        return config.getString();
    }
};

template <>
struct ConfigDumper<float3>
{
    static Config dump(Dumper&, float3 v);
    static float3 undump(Undumper& un, const Config &config);
};

/// ConfigDumper for enum types.
template <typename T>
struct ConfigDumper<T, std::enable_if_t<std::is_enum<T>::value>>
{
    static Config dump(Dumper&, T t) {
        return static_cast<Config::Int>(t);
    }
    static T undump(Undumper&, const Config &config)
    {
        return static_cast<T>(config.getInt());
    }
};

/// ConfigDumper for structs with reflection information.
template <typename T>
struct ConfigDumper<T, std::enable_if_t<MemberVarsAvailable<std::remove_const_t<T>>::value>>
{
    template <typename TT>  // Const or not.
    static Config dump(Dumper& dumper, TT& t)
    {
        Config::Dictionary dict;
        MemberVars<T>::foreach(detail::DumpHandler{&dict, &dumper}, &t);
        return std::move(dict);
    }
};

/// ConfigDumper for pointer-like (dereferenceable) types. Redirects to the
/// underlying object if not nullptr, otherwise returns a "<nullptr>" string.
template <typename T>
struct ConfigDumper<T, std::enable_if_t<is_dereferenceable<T>::value>>
{
    static Config dump(Dumper& dumper, const T& ptr)
    {
        return ptr ? dumper(*ptr) : "<nullptr>";
    }
};

/// ConfigDumper for std::vector<T>.
template <typename T>
struct ConfigDumper<std::vector<T>>
{
    template <typename Vector>  // Const or not.
    static Config dump(Dumper& dumper, Vector& values)
    {
        Config::List list;
        list.reserve(values.size());
        for (auto& value : values)
            list.push_back(dumper(value));
        return std::move(list);
    }
};

/// ConfigDumper for std::map<std::string, T>.
template <typename T>
struct ConfigDumper<std::map<std::string, T>>
{
    template <typename Map>  // Const or not.
    static Config dump(Dumper& dumper, Map& values)
    {
        Config::Dictionary dict;
        dict.reserve(values.size());
        for (auto& pair : values)
            dict.unsafe_insert(pair.first, dumper(pair.second));
        return std::move(dict);
    }
};

/// ConfigDumper for mpark::variant.
template <typename... Ts>
struct ConfigDumper<mpark::variant<Ts...>>
{
    template <typename Variant>  // Const or not.
    static Config dump(Dumper& dumper, Variant& value)
    {
        Config::Dictionary dict;
        dict.reserve(2);
        dict.unsafe_insert("__index", static_cast<Config::Int>(value.index()));
        dict.unsafe_insert("value", mpark::visit(dumper, value));
        return dict;
    }
};

Config configFromJSONFile(const std::string& filename);
Config configFromJSON(const std::string& json);

} // namespace mirheo
