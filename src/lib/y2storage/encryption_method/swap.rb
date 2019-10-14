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

require "y2storage/encryption_method/base"
require "y2storage/encryption_processes/volatile"

module Y2Storage
  module EncryptionMethod
    class Swap < Base
      # @see Base#used_for?
      def used_for?(encryption)
        used?(encryption.key_file, encryption.crypt_options)
      end

      # @see Base#used_for_crypttab?
      def used_for_crypttab?(entry)
        used?(entry.password, entry.crypt_options)
      end

      # @see Base#only_for_swap?
      def only_for_swap?
        true
      end

      # @see Base#exist?
      def available?
        File.exist?(key_file)
      end

      # Encryption key file
      #
      # Each Swap process could use a different key file.
      #
      # @raise [RuntimeError] if no key file has been defined.
      #
      # @return [String]
      def key_file
        self.class.const_get(:KEY_FILE)
      rescue NameError
        raise "No key file indicated!"
      end

      # Encryption cipher
      #
      # Each Swap process could use a different cipher.
      #
      # @return [String, nil] nil if no specific cipher
      def cipher
        self.class.const_get(:CIPHER)
      rescue NameError
        nil
      end

      # Size of the encryption key
      #
      # @return [String, nil] nil if no specific size
      def key_size
        self.class.const_get(:KEY_SIZE)
      rescue NameError
        nil
      end

      # Sector size for the encryption
      #
      # @return [String, nil] nil if no specific sector size
      def sector_size
        self.class.const_get(:SECTOR_SIZE)
      rescue NameError
        nil
      end

      private

      SWAP_OPTION = "swap".freeze

      # Checks whether the process was used according to the given key file and encrytion options
      #
      # @param key_file [String]
      # @param crypt_options [Array<String>]
      def used?(key_file, crypt_options)
        contain_swap_option?(crypt_options) && use_key_file?(key_file)
      end

      # Whether the given encryption device contains the swap option
      #
      # @param crypt_options [Array<String>]
      # @return [Boolean]
      def contain_swap_option?(crypt_options)
        crypt_options.any? { |o| o.casecmp?(SWAP_OPTION) }
      end

      # Whether the given encryption device is using the key file for this process
      #
      # @param key_file [String]
      # @return [Boolean]
      def use_key_file?(key_file)
        key_file == self.key_file
      end

      # @see Base#encryption_process
      def encryption_process
        EncryptionProcesses::Volatile.new(
          self, key_file: key_file, cipher: cipher, key_size: key_size, sector_size: sector_size
        )
      end
    end
  end
end
