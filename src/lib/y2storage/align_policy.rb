require "y2storage/storage_enum_wrapper"

module Y2Storage
  # Class to represent all the possible align policies implemented by libstorage
  #
  # This is a wrapper for the Storage::AlignPolicy enum
  class AlignPolicy
    include StorageEnumWrapper

    wrap_enum "AlignPolicy"
  end
end