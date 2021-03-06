#!/usr/bin/env rspec
# Copyright (c) [2018] SUSE LLC
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

require_relative "../test_helper"

require "cwm/rspec"
require "y2partitioner/dialogs/import_mount_points"
require "y2partitioner/actions/controllers/fstabs"

describe Y2Partitioner::Dialogs::ImportMountPoints do
  before do
    devicegraph_stub(scenario)
  end

  let(:scenario) { "mixed_disks.yml" }

  let(:controller) { Y2Partitioner::Actions::Controllers::Fstabs.new }

  subject { described_class.new(controller) }

  include_examples "CWM::Dialog"

  describe "#contents" do
    it "contains a widget for selecting a fstab" do
      widget = subject.contents.nested_find do |w|
        w.is_a?(Y2Partitioner::Widgets::FstabSelector)
      end

      expect(widget).to_not be_nil
    end

    it "contains a widget for selecting to format system devices" do
      widget = subject.contents.nested_find do |w|
        w.is_a?(Y2Partitioner::Dialogs::ImportMountPoints::FormatWidget)
      end

      expect(widget).to_not be_nil
    end
  end

  describe Y2Partitioner::Dialogs::ImportMountPoints::FormatWidget do
    subject { Y2Partitioner::Dialogs::ImportMountPoints::FormatWidget.new(controller) }

    include_examples "CWM::CheckBox"
  end
end
