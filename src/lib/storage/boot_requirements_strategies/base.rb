#!/usr/bin/env ruby
#
# encoding: utf-8

# Copyright (c) [2015] SUSE LLC
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

require "yast"
require "storage/patches"
require "storage/disk_size"
require "storage/planned_volume"
require "storage/planned_volumes_list"

module Yast
  module Storage
    module BootRequirementsStrategies
      class Error < RuntimeError
      end

      # Base class for the strategies used to calculate the boot partitioning
      # requirements
      class Base
        include Yast::Logger

        def initialize(settings, disk_analyzer)
          @settings = settings
          @disk_analyzer = disk_analyzer
          @root_disk = @disk_analyzer.device_by_name(settings.root_device)
        end

        def needed_partitions
          volumes = PlannedVolumesList.new
          volumes << boot_volume if boot_partition_needed?
          volumes << grub_volume if grub_partition_needed? && grub_partition_missing?
          volumes
        end

      protected

        attr_reader :settings
        attr_reader :disk_analyzer
        attr_reader :root_disk

        def boot_partition_needed?
          # FIXME: so far we don't create partition tables, so we just analyze
          # the existing one.
          root_ptable_type?(:msdos) && settings.use_lvm #TODO: || settings.encrypted
        end

        def grub_partition_needed?
          # FIXME: see above for note above existing partition tables
          root_ptable_type?(:gpt) && settings.use_lvm # TODO: || settings.encrypted
        end

        def grub_partition_missing?
          partitions = disk_analyzer.grub_partitions[settings.root_device]
          partitions.nil? || partitions.empty?
        end

        def boot_volume
          vol = PlannedVolume.new("/boot", ::Storage::FsType_EXT4)
          vol.disk = settings.root_device
          vol.min_disk_size = DiskSize.MiB(100)
          vol.max_disk_size = DiskSize.MiB(500)
          vol.desired_disk_size = DiskSize.MiB(200)
          vol.can_live_on_logical_volume = false
          vol
        end

        def grub_volume
          vol = PlannedVolume.new(nil)
          # only required on GPT
          vol.partition_id = ::Storage::ID_GPT_BIOS
          vol.min_disk_size = DiskSize.KiB(256)
          vol.max_disk_size = DiskSize.MiB(8)
          vol.desired_disk_size = DiskSize.MiB(1)
          vol.align = :keep_size
          vol.bootable = false
          vol.can_live_on_logical_volume = false
          vol
        end

        def root_ptable_type
          return nil unless root_disk
          return nil unless root_disk.partition_table?
          root_disk.partition_table.type
        end

        def root_ptable_type?(type)
          if !type.is_a?(Fixnum)
            type = ::Storage.const_get(:"PtType_#{type.to_s.upcase}")
          end
          root_ptable_type == type
        end
      end
    end
  end
end
