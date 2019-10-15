# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "y2storage/encryption_method/luks1"
require "y2storage/encryption_method/pervasive_luks2"
require "y2storage/encryption_method/random_swap"
require "y2storage/encryption_method/protected_swap"
require "y2storage/encryption_method/secure_swap"

module Y2Storage
  # YaST provides different Encryption Methods to encrypt a block device. Not to be confused with the
  # encryption type ({EncryptionType} class) that represents the encryption technology used underneath
  # (e.g., LUKS1, PLAIN, etc).
  #
  # An Encryption Method is identified by a name and it encapsulates a set of steps to encrypt the
  # device.
  #
  # This class offers a catalog of possible Encryption Methods, see {EncryptionMethod.all}.
  #
  # @example
  #
  #   EncryptionMethod.all.first
  #   EncryptionMethod.available.first
  #   EncryptionMethod.find(:luks1)
  #   EncryptionMethod.find(:random_swap)
  module EncryptionMethod
    LUKS1 = Luks1.new
    PERVASIVE_LUKS2 = PervasiveLuks2.new
    RANDOM_SWAP = RandomSwap.new
    PROTECTED_SWAP = ProtectedSwap.new
    SECURE_SWAP = SecureSwap.new
    ALL = [
      LUKS1, PERVASIVE_LUKS2, RANDOM_SWAP, PROTECTED_SWAP, SECURE_SWAP
    ]

    # Sorted list of all possible encryption methods
    #
    # @return [Array<Y2Storage::EncryptionMethod>]
    def self.all
      ALL.dup
    end

    # Sorted list of all encryption methods that can be used in this system
    #
    # @return [Array<Y2Storage::EncryptionMethod>]
    def self.available
      all.select(&:available?)
    end

    # Looks for the encryption method used for the given encryption device
    #
    # @param encryption [Y2Storage::Encryption]
    # @return [Y2Storage::EncryptionMethod, nil]
    def self.for_device(encryption)
      all.find { |m| m.used_for?(encryption) }
    end

    # Looks for the encryption method used for the given crypttab entry
    #
    # @param entry [Y2Storage::SimpleEtcCrypttabEntry]
    # @return [Y2Storage::EncryptionMethod, nil]
    def self.for_crypttab(entry)
      all.find { |m| m.used_for_crypttab?(entry) }
    end

    # Looks for the encryption method by its symbol representation
    #
    # @param value [#to_sym]
    # @return [Y2Storage::EncryptionMethod, nil] the encryption method found if any; nil otherwise
    def self.find(value)
      all.find { |i| i.is?(value) }
    end
  end
end
