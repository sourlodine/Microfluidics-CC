#include "file_wrapper.h"
#include <mirheo/core/logger.h>

namespace mirheo
{

FileWrapper::FileWrapper(bool forceFlushOnClose) :
    forceFlushOnClose_(forceFlushOnClose)
{}

FileWrapper::FileWrapper(const std::string& fname, const std::string& mode,
                         bool forceFlushOnClose) :
    forceFlushOnClose_(forceFlushOnClose)
{
    if (open(fname, mode) != FileWrapper::Status::Success) {
        die("Could not open the file \"%s\" in mode \"%s\".",
            fname.c_str(), mode.c_str());
    }
}

FileWrapper::~FileWrapper()
{
    close();
}

FileWrapper::Status FileWrapper::open(const std::string& fname, const std::string& mode)
{
    if (needClose_) close();

    file_ = fopen(fname.c_str(), mode.c_str());

    if (file_ == nullptr)
        return Status::Failed;

    needClose_ = true;
    return Status::Success;
}

FileWrapper::Status FileWrapper::open(FileWrapper::SpecialStream stream)
{
    if (needClose_) close();

    switch(stream)
    {
    case SpecialStream::Cout: file_ = stdout; break;
    case SpecialStream::Cerr: file_ = stderr; break;
    }

    needClose_ = false;
    return Status::Success;
}

void FileWrapper::close()
{
    if (needClose_)
    {
        if (forceFlushOnClose_)
            fflush(file_);
        fclose(file_);
        needClose_ = false;
    }
}

} // namespace mirheo
