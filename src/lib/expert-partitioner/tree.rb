

require "yast"
require "storage"
require "storage/storage-manager"
require "storage/extensions"
require "expert-partitioner/views/all"
require "expert-partitioner/views/disk"
require "expert-partitioner/views/partition"
require "expert-partitioner/views/filesystem"
require "expert-partitioner/views/probed-devicegraph"
require "expert-partitioner/views/staging-devicegraph"
require "expert-partitioner/views/actiongraph"
require "expert-partitioner/views/actionlist"

Yast.import "UI"
Yast.import "Label"
Yast.import "Popup"
Yast.import "Directory"
Yast.import "HTML"

include Yast::I18n


module ExpertPartitioner

  class Tree

    include Yast::UIShortcuts
    include Yast::Logger


    def initialize
      textdomain "storage"
    end


    def tree_items
      [
        Item(
          Id(:all), "hostname", true,
          [
            Item(Id(:hd), _("Hard Disks"), true, disks_subtree_items()),
            Item(Id(:filesystems), _("Filesystems"))
          ]
        ),
        Item(Id(:devicegraph_probed), _("Device Graph (probed)")),
        Item(Id(:devicegraph_staging), _("Device Graph (staging)")),
        Item(Id(:actiongraph), _("Action Graph")),
        Item(Id(:actionlist), _("Action List"))
      ]
    end


    private


    def disks_subtree_items

      storage = Yast::Storage::StorageManager.instance
      staging = storage.staging()

      disks = Storage::Disk::all(staging)

      return disks.to_a.map do |disk|

        partitions_subtree = []

        begin
          partition_table = disk.partition_table()
          partition_table.partitions().each do |partition|
            partitions_subtree << Item(Id(partition.sid()), partition.name())
          end
        rescue Storage::WrongNumberOfChildren, Storage::DeviceHasWrongType
        end

        Item(Id(disk.sid()), disk.name(), true, partitions_subtree)

      end

    end

  end

end
