# Copyright (c) [2020] SUSE LLC
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
require "cwm"
require "y2partitioner/widgets/menus/system"
require "y2partitioner/widgets/menus/add"
require "y2partitioner/widgets/menus/partitions"
require "y2partitioner/widgets/menus/lvs"
require "y2partitioner/widgets/menus/subvolumes"
require "y2partitioner/widgets/menus/configure"
require "y2partitioner/widgets/menus/modify"

module Y2Partitioner
  module Widgets
    # Main menu bar of the partitioner
    class MainMenuBar < CWM::CustomWidget
      Yast.import "UI"
      include Yast::Logger

      # @return [Y2Storage::Device] current target for the actions
      attr_reader :device

      attr_reader :menus

      # Constructor
      def initialize
        self.handle_all_events = true
        @device = nil
        @menus = calculate_menus
        super
      end

      # Sets the target device
      #
      # As a consequence, the displayed buttons are recalculated and redrawn
      # to reflect the new device.
      #
      # @param dev [Y2Storage::Device] new target
      def device=(dev)
        @device = dev
        @menus = calculate_menus
        refresh
      end

      # Called by CWM after the widgets are created
      def init
        refresh
      end

      def id
        :menu_bar
      end

      # Widget contents
      def contents
        @contents ||= MenuBar(Id(id), items)
      end

      # Event handler for the main menu.
      #
      # @param event [Hash] UI event
      #
      def handle(event)
        return nil unless menu_event?(event)

        id = event["ID"]
        result = nil
        menus.find do |menu|
          result = menu.handle(id)
        end
        result
      end

      private

      # Check if a UI event is a menu event
      def menu_event?(event)
        event["EventType"] == "MenuEvent"
      end

      def items
        menus.map { |m| Menu(Id(m.id), m.label, m.items) }
      end

      def disabled_items
        menus.flat_map { |m| m.disabled_items }
      end

      # Redraws the widget
      def refresh
        Yast::UI.ChangeWidget(Id(id), :Items, items)
        disable_menu_items(*disabled_items)
        disable_menu_items(*disabled_menus)
      end

      # List of buttons that make sense for the current target device
      def calculate_menus
        general_menus + device_menus
      end

      def general_menus
        @general_menus ||= [
          Menus::System.new,
          Menus::Configure.new,
          Menus::Add.new
        ]
      end

      def device_menus
        return [] if device.nil?

        entries = [Menus::Modify.new(device)]
        entries << Menus::Partitions.new(device)
        entries << Menus::Lvs.new(device)
        entries << Menus::Subvolumes.new(device)
        entries
      end

      def disabled_menus
        return [:m_modify, :m_partitions, :m_lvs, :m_subvolumes] if device.nil?

        disabled = []

        if !device.is?(:disk_device, :software_raid, :partition)
          disabled << :m_partitions
        end
        if !device.is?(:lvm_vg, :lvm_lv)
          disabled << :m_lvs
        end
        if !subvolumes?
          disabled << :m_subvolumes
        end

        disabled
      end

      def subvolumes?
        return true if device.is?(:btrfs)

        device.is?(:blk_device) && device.formatted_as?(:btrfs)
      end

      def disable_menu_items(*ids)
        disabled_hash = ids.each_with_object({}) { |id, h| h[id] = false }
        Yast::UI.ChangeWidget(Id(id), :EnabledItems, disabled_hash)
      end
    end
  end
end
