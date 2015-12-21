
require "yast"
require "storage"
require "storage/storage-manager"

Yast.import "UI"
Yast.import "Label"
Yast.import "Popup"


module ExpertPartitioner

  class CreatePartitionDialog

    include Yast::UIShortcuts
    include Yast::I18n
    include Yast::Logger


    def initialize(disk)
      textdomain "storage"
      @disk = disk
    end


    def run
      return nil unless create_dialog

      begin
        case input = Yast::UI.UserInput
        when :cancel
          nil
        when :ok
          doit
        else
          raise "Unexpected input #{input}"
        end
      ensure
        Yast::UI.CloseDialog
      end
    end


    private


    def create_dialog
      Yast::UI.OpenDialog(
        VBox(
          Heading(_("Create Partition")),
          MinWidth(15, InputField(Id(:size_input), Opt(:shrinkable), _("Size"), "50 MiB")),
          ButtonBox(
            PushButton(Id(:cancel), Yast::Label.CancelButton),
            PushButton(Id(:ok), Yast::Label.OKButton)
          )
        )
      )
    end


    def doit

      storage = Yast::Storage::StorageManager.instance

      staging = storage.staging()

      size = Yast::UI.QueryWidget(Id(:size_input), :Value)
      size_k = Storage::humanstring_to_byte(size, false) / 1024

      partition_table = @disk.partition_table()

      partition_slots = partition_table.unused_partition_slots().to_a

      partition_slots.delete_if do |partition_slot|
        !partition_slot.primary_slot || !partition_slot.primary_possible ||
          size_k > partition_slot.region.to_kb(partition_slot.region.length)
      end

      if partition_slots.empty?
        Yast::Popup::Error("No suitable partition slot found.")
        return
      end

      # TODO sort so that smallest slot is first

      partition_slot = partition_slots[0]

      partition_slot.region.length = partition_slot.region.to_value(size_k)

      partition = partition_table.create_partition(partition_slot.name, partition_slot.region,
                                                   Storage::PRIMARY)

    end

  end

end
