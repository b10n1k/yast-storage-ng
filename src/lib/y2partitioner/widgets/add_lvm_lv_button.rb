# encoding: utf-8

# Copyright (c) [2017] SUSE LLC
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
require "y2partitioner/actions/add_lvm_lv"

module Y2Partitioner
  module Widgets
    # Button for opening the workflow to add a logical volume to a volume group
    class AddLvmLvButton < CWM::PushButton
      # Constructor
      # @param vg [Y2Storage::LvmVg]
      def initialize(vg)
        textdomain "storage"
        @vg = vg
      end

      # @macro seeAbstractWidget
      def label
        # TRANSLATORS: button label to add a logical volume
        _("Add...")
      end

      # @macro seeAbstractWidget
      def handle
        res = Actions::AddLvmLv.new(@vg).run
        res == :finish ? :redraw : nil
      end
    end
  end
end
