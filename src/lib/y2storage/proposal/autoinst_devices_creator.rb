# encoding: utf-8

# Copyright (c) [2017-2019] SUSE LLC
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

require "y2storage/proposal/partitions_distribution_calculator"
require "y2storage/proposal/partition_creator"
require "y2storage/proposal/md_creator"
require "y2storage/proposal/nfs_creator"
require "y2storage/proposal/autoinst_creator_result"
require "y2storage/exceptions"

module Y2Storage
  module Proposal
    # Class to create and reuse devices during the AutoYaST proposal, based
    # on the information contained in the profile.
    #
    # ## Comparison with the guided proposal
    #
    # This class receives a devicegraph in which the previous devices have
    # already been deleted or resized according to the AutoYaST profile. This
    # is different from the guided setup equivalent step, in which the minimal
    # amount of existing devices are deleted/resized on demand while trying to
    # allocate the planned devices.
    #
    # ## Reducing planned devices when there is not enough space
    #
    # Another key difference with the guided proposal is that, when there is
    # not enough space (for partitions or logical volumes), it will do a second
    # attempt reducing all planned devices proportionally. In order to do so,
    # it will remove the min_size limit (setting it to just 1 byte) and,
    # additionally, it will set a proportional weight for every partition (see
    # {#flexible_devices}).
    #
    # Although this approach may not produce the optimal results, it is less
    # intrusive and easier to maintain than other alternatives. Bear in mind
    # that AutoYaST does not expect complex scenarios (like multiple disks with
    # several gaps), so the result should be good enough.
    #
    # If we were aiming for the optimal devices distribution, we should look at
    # {Y2Storage::Planned::PartitionsDistribution#assigned_space} and follow
    # the same approach (reducing min_size and setting a proportional weight)
    # when it is not possible to place the devices in the given free space. But
    # we would also need to do further changes, like skipping some checks when
    # running in this flexible mode.
    class AutoinstDevicesCreator
      include Yast::Logger

      # @return [AutoinstIssues::List] List of found AutoYaST issues
      attr_reader :issues_list

      # Constructor
      #
      # @param original_graph [Devicegraph] Devicegraph to be used as starting point
      # @param issues_list [AutoinstIssues::List] List of AutoYaST issues to register them
      def initialize(original_graph, issues_list)
        @original_graph = original_graph
        @issues_list = issues_list
      end

      # Devicegraph including all the specified planned devices
      #
      # @param planned_devices [Planned::DevicesCollection] Devices to create/reuse
      # @param disk_names [Array<String>] Disks to consider
      #
      # @return [AutoinstCreatorResult] Result with new devicegraph in which all the
      #   planned devices have been allocated
      def populated_devicegraph(planned_devices, disk_names)
        # Process planned partitions
        log.info "planned devices = #{planned_devices.to_a.inspect}"
        log.info "disk names = #{disk_names.inspect}"

        reset

        @planned_devices = planned_devices
        @disk_names = disk_names

        process_devices
      end

    protected

      # @return [Devicegraph] Original devicegraph
      attr_reader :original_graph

      # @return [Planned::DevicesCollection] Devices to create/reuse
      attr_reader :planned_devices

      # @return [Array<String>] Disks to consider
      attr_reader :disk_names

      # @return [Array<Planned::Device>] Devices to create
      attr_reader :devices_to_create

      # @return [Array<Planned::Device>] Devices to reuse
      attr_reader :devices_to_reuse

      # @return [Proposal::CreatorResult] Current result containing the devices that have been created
      attr_reader :creator_result

      # @return [Devicegraph] Current devicegraph
      attr_reader :devicegraph

      # Finds the best distribution for the given planned partitions
      #
      # @see Proposal::PartitionsDistributionCalculator#best_distribution
      #
      # @param planned_partitions [Array<Planned::Partition>] Partitions to add
      # @return [Planned::PartitionsDistribution]
      def best_distribution(planned_partitions)
        disks = devicegraph.disk_devices.select { |d| disk_names.include?(d.name) }
        spaces = disks.map(&:free_spaces).flatten

        calculator = Proposal::PartitionsDistributionCalculator.new
        dist = calculator.best_distribution(planned_partitions, spaces)
        return dist if dist

        # Second try with more flexible planned partitions
        calculator.best_distribution(flexible_devices(planned_partitions), spaces)
      end

    private

      # Sets the current creator result
      #
      # The current devicegraph is properly updated.
      #
      # @param result [Proposal::CreatorResult]
      def creator_result=(result)
        @creator_result = result
        @devicegraph = result.devicegraph
      end

      # Adds devices to the list of devices to create
      #
      # @param planned_devices [Array<Planned::Device>]
      def add_devices_to_create(planned_devices)
        @devices_to_create.concat(planned_devices)
      end

      # Adds devices to the list of devices to reuse
      #
      # @param planned_devices [Array<Planned::Device>]
      def add_devices_to_reuse(planned_devices)
        @devices_to_reuse.concat(planned_devices)
      end

      # Resets values before create devices
      #
      # @see #populated_devicegraph
      def reset
        @devices_to_create = []
        @devices_to_reuse = []
        @creator_result = nil
        @devicegraph = original_graph.duplicate
      end

      # Reuses and creates planned devices
      #
      # @return [AutoinstCreatorResult] Result with new devicegraph in which all the
      #   planned devices have been allocated
      def process_devices
        process_partitions
        # Process planned disk like devices (Xen virtual partitions and full disks)
        process_disk_like_devs
        process_mds
        process_bcaches
        process_vgs
        process_nfs_filesystems

        Y2Storage::Proposal::AutoinstCreatorResult.new(creator_result, devices_to_create)
      end

      # Process planned partitions
      def process_partitions
        planned_partitions = sized_partitions(planned_devices.disk_partitions)
        parts_to_reuse, parts_to_create = planned_partitions.partition(&:reuse?)
        reuse_partitions(parts_to_reuse)

        add_devices_to_create(parts_to_create)
        add_devices_to_reuse(parts_to_reuse)
        self.creator_result = create_partitions(parts_to_create)
      end

      # Formats and/or mounts the disk like block devices (Xen virtual partitions and full disks)
      #
      # Add planned disk like devices to reuse list so they can be considered for lvm and raids
      # later on.
      def process_disk_like_devs
        planned_devs = planned_devices.select do |dev|
          dev.is_a?(Planned::StrayBlkDevice) || dev.is_a?(Planned::Disk)
        end

        planned_devs.each { |d| d.reuse!(devicegraph) }

        add_devices_to_reuse(planned_devs)
      end

      # Process planned Mds
      def process_mds
        mds_to_reuse, mds_to_create = planned_devices.mds.partition(&:reuse?)
        devs_to_reuse_in_md = reusable_by_md(devices_to_reuse)
        reuse_mds(mds_to_reuse)

        add_devices_to_create(mds_to_create)
        add_devices_to_reuse(mds_to_reuse.flat_map(&:partitions))
        self.creator_result = create_mds(planned_devices.mds, devs_to_reuse_in_md)
      end

      # Process planned bcaches
      def process_bcaches
        bcaches_to_reuse, bcaches_to_create = planned_devices.bcaches.partition(&:reuse?)
        reuse_bcaches(bcaches_to_reuse)

        add_devices_to_create(bcaches_to_create)
        add_devices_to_reuse(bcaches_to_reuse.flat_map(&:partitions))
        self.creator_result = create_bcaches(planned_devices.bcaches, devices_to_reuse)
      end

      # Process planned Vgs
      def process_vgs
        planned_vgs = planned_devices.vgs
        vgs_to_reuse = planned_vgs.select(&:reuse?)
        reuse_vgs(vgs_to_reuse)

        add_devices_to_create(planned_vgs)
        self.creator_result = set_up_lvm(planned_vgs, devices_to_reuse)
      end

      # Process planned NFS filesystems
      def process_nfs_filesystems
        add_devices_to_create(planned_devices.nfs_filesystems)
        self.creator_result = create_nfs_filesystems(planned_devices.nfs_filesystems)
      end

      # Reuses partitions for the given devicegraph
      #
      # Shrinking partitions/logical volumes should be processed first in order to free
      # some space for growing ones.
      #
      # @param reused_devices  [Array<Planned::Partition>] Partitions to reuse
      def reuse_partitions(reused_devices)
        shrinking, not_shrinking = reused_devices.partition { |d| d.shrink?(devicegraph) }
        (shrinking + not_shrinking).each { |d| d.reuse!(devicegraph) }
      end

      # Reuses MD RAIDs for the given devicegraph
      #
      # @param reused_mds [Array<Planned::Md>] MD RAIDs to reuse
      def reuse_mds(reused_mds)
        reused_mds.each_with_object(creator_result) do |md, result|
          md_creator = Proposal::MdCreator.new(result.devicegraph)
          result.merge!(md_creator.reuse_partitions(md))
        end
      end

      # Reuses bcaches for the given devicegraph
      #
      # @param reused_bcaches [Array<Planned::Bcache>] bcaches to reuse
      def reuse_bcaches(reused_bcaches)
        reused_bcaches.each_with_object(creator_result) do |bcache, result|
          bcache_creator = Proposal::BcacheCreator.new(result.devicegraph)
          result.merge!(bcache_creator.reuse_partitions(bcache))
        end
      end

      # Reuses volume groups for the given devicegraph
      #
      # @param reused_vgs [Array<Planned::LvmVg>] Volume groups to reuse
      def reuse_vgs(reused_vgs)
        reused_vgs.each_with_object(creator_result) do |vg, result|
          lvm_creator = Proposal::LvmCreator.new(result.devicegraph)
          result.merge!(lvm_creator.reuse_volumes(vg))
        end
      end

      # Creates planned partitions
      #
      # @param new_partitions [Array<Planned::Partition>] Devices to create
      # @return [PartitionCreatorResult]
      def create_partitions(new_partitions)
        log.info "Partitions to create: #{new_partitions}"
        primary, non_primary = new_partitions.partition(&:primary)
        parts_to_create = primary + non_primary

        dist = best_distribution(parts_to_create)
        raise NoDiskSpaceError, "Could not find a valid partitioning distribution" if dist.nil?
        part_creator = Proposal::PartitionCreator.new(devicegraph)
        part_creator.create_partitions(dist)
      end

      # Creates MD RAID devices in the given devicegraph
      #
      # @param mds [Array<Planned::Md>] List of planned MD arrays to create
      # @param devs_to_reuse [Array<Planned::Partition, Planned::StrayBlkDevice>] List of devices
      #   to reuse
      #
      # @return [Proposal::CreatorResult] Result containing the specified MD RAIDs
      def create_mds(mds, devs_to_reuse)
        mds.reduce(creator_result) do |result, md|
          # Normally, the profile will use the same naming convention
          # (/dev/md0 vs /dev/md/0) to define the RAID itself (in its corresponding
          # <drive> section) and to reference that RAID from its components
          # (using <raid_name>). So populating the 'devices' list below could be
          # as simple as matching Planned::Devices#raid_name with Planned::Md.name
          #
          # BUT if the old format is used to specify the RAID ("/dev/md" as name
          # and a <partition_nr> to indicate the number), the name for the planned MD
          # is auto-generated (with the /dev/md/0 format so far), so we must use
          # Planned::Md#name? to ensure robust comparison no matter which format
          # is used in #raid_name
          devices = result.created_names { |d| d.respond_to?(:raid_name) && md.name?(d.raid_name) }
          devices += devs_to_reuse.select { |d| md.name?(d.raid_name) }.map(&:reuse_name)
          result.merge(create_md(result.devicegraph, md, devices))
        end
      end

      # Creates bcaches
      #
      # @param bcaches [Array<Planned::Bcache>] List of planned MD arrays to create
      # @param devs_to_reuse [Array<Planned::Partition, Planned::StrayBlkDevice>] List of devices
      #   to reuse
      #
      # @return [Proposal::CreatorResult] Result containing the specified MD RAIDs
      def create_bcaches(bcaches, devs_to_reuse)
        bcaches.reduce(creator_result) do |result, bcache|
          backing_devname = find_bcache_member(bcache.name, :backing, creator_result, devs_to_reuse)
          caching_devname = find_bcache_member(bcache.name, :caching, creator_result, devs_to_reuse)
          new_result = create_bcache(result.devicegraph, bcache, backing_devname, caching_devname)
          result.merge(new_result)
        end
      end

      # Creates volume groups
      #
      # @param vgs [Array<Planned::LvmVg>] List of planned volume groups to add
      # @param devs_to_reuse [Array<Planned::Partition, Planned::StrayBlkDevice>] List of devices
      #   to reuse as Physical Volumes
      #
      # @return [Proposal::CreatorResult] Result containing the specified volume groups
      def set_up_lvm(vgs, devs_to_reuse)
        # log separately to be more readable
        log.info "set_up_lvm: vgs=#{vgs.inspect}"
        log.info "set_up_lvm: previous_result=#{creator_result.inspect}"
        log.info "set_up_lvm: devs_to_reuse=#{devs_to_reuse.inspect}"

        vgs.reduce(creator_result) do |result, vg|
          pvs = creator_result.created_names { |d| d.pv_for?(vg.volume_group_name) }
          pvs += devs_to_reuse.select { |d| d.pv_for?(vg.volume_group_name) }.map(&:reuse_name)
          if pvs.empty?
            issues_list.add(:no_pvs, vg)
            next result
          end

          result.merge(create_logical_volumes(result.devicegraph, vg, pvs))
        end
      end

      # Creates NFS filesystems
      #
      # @param nfs_filesystems [Array<Planned::Nfs>] List of planned NFS filesystems
      # @return [Proposal::CreatorResult] Result containing the specified NFS filesystems
      def create_nfs_filesystems(nfs_filesystems)
        nfs_filesystems.reduce(creator_result) do |result, planned_nfs|
          new_result = create_nfs_filesystem(result.devicegraph, planned_nfs)
          result.merge(new_result)
        end
      end

      # Creates a MD RAID
      #
      # @param devicegraph [Devicegraph] Starting devicegraph
      # @param md          [Planned::Md] Planned MD RAID
      # @param devices     [Array<Planned::Device>] List of devices to include in the RAID
      # @return            [Proposal::CreatorResult] Result containing the specified RAID
      #
      # @raise NoDiskSpaceError
      def create_md(devicegraph, md, devices)
        md_creator = Proposal::MdCreator.new(devicegraph)
        md_creator.create_md(md, devices)
      rescue NoDiskSpaceError
        md_creator = Proposal::MdCreator.new(devicegraph)
        new_md = md.clone
        new_md.partitions = flexible_devices(md.partitions)
        md_creator.create_md(new_md, devices)
      end

      # Creates a bcache
      #
      # @param devicegraph     [Devicegraph] Starting devicegraph
      # @param bcache          [Planned::Bcache] Planned bcache
      # @param backing_devname [String] Backing device name
      # @param caching_devname [String] Caching device name
      # @return [Proposal::CreatorResult] Result containing the specified bcache
      def create_bcache(devicegraph, bcache, backing_devname, caching_devname)
        bcache_creator = Proposal::BcacheCreator.new(devicegraph)
        bcache_creator.create_bcache(bcache, backing_devname, caching_devname)
      rescue NoDiskSpaceError
        bcache_creator = Proposal::BcacheCreator.new(devicegraph)
        new_bcache = bcache.clone
        new_bcache.partitions = flexible_devices(bcache.partitions)
        bcache_creator.create_bcache(new_bcache, backing_devname, caching_devname)
      end

      # Creates a volume group in the given devicegraph
      #
      # @param devicegraph [Devicegraph]                    Starting devicegraph
      # @param vg          [Planned::LvmVg]                 Volume group
      # @param pvs         [Planned::Partition,Planned::Md] List of physical volumes
      # @return            [Proposal::CreatorResult] Result containing the specified volume group
      def create_logical_volumes(devicegraph, vg, pvs)
        lvm_creator = Proposal::LvmCreator.new(devicegraph)
        lvm_creator.create_volumes(vg, pvs)
      rescue RuntimeError => error
        log.error error.message
        lvm_creator = Proposal::LvmCreator.new(devicegraph)
        new_vg = vg.clone
        new_vg.lvs = flexible_devices(vg.lvs)
        lvm_creator.create_volumes(new_vg, pvs)
      end

      # Creates a NFS filesystem
      #
      # @param devicegraph [Devicegraph] Starting devicegraph
      # @param planned_nfs [Planned::Nfs]
      #
      # @return [Proposal::CreatorResult] Result containing the specified NFS
      def create_nfs_filesystem(devicegraph, planned_nfs)
        nfs_creator = Proposal::NfsCreator.new(devicegraph)
        nfs_creator.create_nfs(planned_nfs)
      end

      # Finds the bcache member in the previous result and the list of devices to use
      #
      # @return [String] Device name
      def find_bcache_member(bcache_name, role, result, devs_to_reuse)
        names = result.created_names { |d| bcache_member_for?(d, bcache_name, role) }
        return names.first unless names.empty?
        device = devs_to_reuse.find { |d| bcache_member_for?(d, bcache_name, role) }
        device && device.reuse_name
      end

      # Determines whether a device plays a given role in a bcache
      #
      # @param device      [Planned::Device] Device to consider
      # @param bcache_name [String] bcache name
      # @param role        [:caching, :backing] Role that the device plays in the bcache device
      # @return [Boolean]
      def bcache_member_for?(device, bcache_name, role)
        query_method = "bcache_#{role}_for?"
        device.respond_to?(query_method) && device.send(query_method, bcache_name)
      end

      # Return a new planned devices with flexible limits
      #
      # The min_size is removed and a proportional weight is set for every device.
      #
      # @return [Hash<Planned::Partition => Planned::Partition>]
      def flexible_devices(devices)
        devices.map do |device|
          new_device = device.clone
          new_device.weight = device.min_size.to_i
          new_device.min_size = DiskSize.B(1)
          new_device
        end
      end

      # Return devices which can be reused by an MD RAID
      #
      # @param planned_devices [Planned::DevicesCollection] collection of planned devices
      # @return [Array<Planned::Device>]
      def reusable_by_md(planned_devices)
        planned_devices.select { |d| d.respond_to?(:raid_name) }
      end

      # Return devices which can be reused by a bcache
      #
      # @param planned_devices [Planned::DevicesCollection] collection of planned devices
      # @return [Array<Planned::Device>]
      def reusable_by_bcache(planned_devices)
        planned_devices.select { |d| d.respond_to?(:bcache_backing_for) }
      end

      # Returns a list of planned partitions adjusting the size
      #
      # All partitions which sizes are specified as percentage will get their minimal and maximal
      # sizes adjusted.
      #
      # @param planned_partitions [Array<Planned::Partition>] List of planned partitions
      # @return [Array<Planned::Partition>] New list of planned partitions with adjusted sizes
      def sized_partitions(planned_partitions)
        planned_partitions.map do |part|
          new_part = part.clone
          next new_part unless new_part.percent_size
          disk = original_graph.find_by_name(part.disk)
          new_part.max = new_part.min = new_part.size_in(disk)
          new_part
        end
      end
    end
  end
end
