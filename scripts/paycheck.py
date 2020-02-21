#!/usr/bin/env python
#
# Copyright (C) 2013 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

"""Command-line tool for checking and applying Chrome OS update payloads."""

from __future__ import absolute_import
from __future__ import print_function

# pylint: disable=import-error
import argparse
import filecmp
import os
import sys
import tempfile

from six.moves import zip
from update_payload import error


lib_dir = os.path.join(os.path.dirname(__file__), 'lib')
if os.path.exists(lib_dir) and os.path.isdir(lib_dir):
  sys.path.insert(1, lib_dir)
import update_payload  # pylint: disable=wrong-import-position


_TYPE_FULL = 'full'
_TYPE_DELTA = 'delta'

def CheckApplyPayload(args):
  """Whether to check the result after applying the payload.

  Args:
    args: Parsed command arguments (the return value of
          ArgumentParser.parse_args).

  Returns:
    Boolean value whether to check.
  """
  return args.dst_part_paths is not None

def ApplyPayload(args):
  """Whether to apply the payload.

  Args:
    args: Parsed command arguments (the return value of
          ArgumentParser.parse_args).

  Returns:
    Boolean value whether to apply the payload.
  """
  return CheckApplyPayload(args) or args.out_dst_part_paths is not None

def ParseArguments(argv):
  """Parse and validate command-line arguments.

  Args:
    argv: command-line arguments to parse (excluding the program name)

  Returns:
    Returns the arguments returned by the argument parser.
  """
  parser = argparse.ArgumentParser(
      description=('Applies a Chrome OS update PAYLOAD to src_part_paths'
                   'emitting dst_part_paths, respectively. '
                   'src_part_paths are only needed for delta payloads. '
                   'When no partitions are provided, verifies the payload '
                   'integrity.'),
      epilog=('Note: a payload may verify correctly but fail to apply, and '
              'vice versa; this is by design and can be thought of as static '
              'vs dynamic correctness. A payload that both verifies and '
              'applies correctly should be safe for use by the Chrome OS '
              'Update Engine. Use --check to verify a payload prior to '
              'applying it.'),
      formatter_class=argparse.RawDescriptionHelpFormatter
  )

  check_args = parser.add_argument_group('Checking payload integrity')
  check_args.add_argument('-c', '--check', action='store_true', default=False,
                          help=('force payload integrity check (e.g. before '
                                'applying)'))
  check_args.add_argument('-D', '--describe', action='store_true',
                          default=False,
                          help='Print a friendly description of the payload.')
  check_args.add_argument('-r', '--report', metavar='FILE',
                          help="dump payload report (`-' for stdout)")
  check_args.add_argument('-t', '--type', dest='assert_type',
                          help='assert the payload type',
                          choices=[_TYPE_FULL, _TYPE_DELTA])
  check_args.add_argument('-z', '--block-size', metavar='NUM', default=0,
                          type=int,
                          help='assert a non-default (4096) payload block size')
  check_args.add_argument('-u', '--allow-unhashed', action='store_true',
                          default=False, help='allow unhashed operations')
  check_args.add_argument('-d', '--disabled_tests', default=(), metavar='',
                          help=('space separated list of tests to disable. '
                                'allowed options include: ' +
                                ', '.join(update_payload.CHECKS_TO_DISABLE)),
                          choices=update_payload.CHECKS_TO_DISABLE)
  check_args.add_argument('-k', '--key', metavar='FILE',
                          help=('override standard key used for signature '
                                'validation'))
  check_args.add_argument('-m', '--meta-sig', metavar='FILE',
                          help='verify metadata against its signature')
  check_args.add_argument('-s', '--metadata-size', metavar='NUM', default=0,
                          help='the metadata size to verify with the one in'
                          ' payload')
  check_args.add_argument('--part_sizes', metavar='NUM', nargs='+', type=int,
                          help='override partition size auto-inference')

  apply_args = parser.add_argument_group('Applying payload')
  # TODO(ahassani): Extent extract-bsdiff to puffdiff too.
  apply_args.add_argument('-x', '--extract-bsdiff', action='store_true',
                          default=False,
                          help=('use temp input/output files with BSDIFF '
                                'operations (not in-place)'))
  apply_args.add_argument('--bspatch-path', metavar='FILE',
                          help='use the specified bspatch binary')
  apply_args.add_argument('--puffpatch-path', metavar='FILE',
                          help='use the specified puffpatch binary')

  apply_args.add_argument('--src_part_paths', metavar='FILE', nargs='+',
                          help='source partitition files')
  apply_args.add_argument('--dst_part_paths', metavar='FILE', nargs='+',
                          help='destination partition files')
  apply_args.add_argument('--out_dst_part_paths', metavar='FILE', nargs='+',
                          help='created destination partition files')

  parser.add_argument('payload', metavar='PAYLOAD', help='the payload file')
  parser.add_argument('--part_names', metavar='NAME', nargs='+',
                      help='names of partitions')

  # Parse command-line arguments.
  args = parser.parse_args(argv)

  # There are several options that imply --check.
  args.check = (args.check or args.report or args.assert_type or
                args.block_size or args.allow_unhashed or
                args.disabled_tests or args.meta_sig or args.key or
                args.part_sizes is not None or args.metadata_size)

  # Makes sure the following arguments have the same length as |part_names| if
  # set.
  for arg in ['part_sizes', 'src_part_paths', 'dst_part_paths',
              'out_dst_part_paths']:
    if getattr(args, arg) is None:
      # Parameter is not set.
      continue
    if len(args.part_names) != len(getattr(args, arg, [])):
      parser.error('partitions in --%s do not match --part_names' % arg)

  def _IsSrcPartPathsProvided(args):
    return args.src_part_paths is not None

  # Makes sure parameters are coherent with payload type.
  if ApplyPayload(args):
    if _IsSrcPartPathsProvided(args):
      if args.assert_type == _TYPE_FULL:
        parser.error('%s payload does not accept source partition arguments'
                     % _TYPE_FULL)
      else:
        args.assert_type = _TYPE_DELTA
    else:
      if args.assert_type == _TYPE_DELTA:
        parser.error('%s payload requires source partitions arguments'
                     % _TYPE_DELTA)
      else:
        args.assert_type = _TYPE_FULL
  else:
    # Not applying payload.
    if args.extract_bsdiff:
      parser.error('--extract-bsdiff can only be used when applying payloads')
    if args.bspatch_path:
      parser.error('--bspatch-path can only be used when applying payloads')
    if args.puffpatch_path:
      parser.error('--puffpatch-path can only be used when applying payloads')

  # By default, look for a metadata-signature file with a name based on the name
  # of the payload we are checking. We only do it if check was triggered.
  if args.check and not args.meta_sig:
    default_meta_sig = args.payload + '.metadata-signature'
    if os.path.isfile(default_meta_sig):
      args.meta_sig = default_meta_sig
      print('Using default metadata signature', args.meta_sig, file=sys.stderr)

  return args


def main(argv):
  # Parse and validate arguments.
  args = ParseArguments(argv[1:])

  with open(args.payload, 'rb') as payload_file:
    payload = update_payload.Payload(payload_file)
    try:
      # Initialize payload.
      payload.Init()

      if args.describe:
        payload.Describe()

      # Perform payload integrity checks.
      if args.check:
        report_file = None
        do_close_report_file = False
        metadata_sig_file = None
        try:
          if args.report:
            if args.report == '-':
              report_file = sys.stdout
            else:
              report_file = open(args.report, 'w')
              do_close_report_file = True

          part_sizes = (args.part_sizes and
                        dict(zip(args.part_names, args.part_sizes)))
          metadata_sig_file = args.meta_sig and open(args.meta_sig, 'rb')
          payload.Check(
              pubkey_file_name=args.key,
              metadata_sig_file=metadata_sig_file,
              metadata_size=int(args.metadata_size),
              report_out_file=report_file,
              assert_type=args.assert_type,
              block_size=int(args.block_size),
              part_sizes=part_sizes,
              allow_unhashed=args.allow_unhashed,
              disabled_tests=args.disabled_tests)
        finally:
          if metadata_sig_file:
            metadata_sig_file.close()
          if do_close_report_file:
            report_file.close()

      # Apply payload.
      if ApplyPayload(args):
        dargs = {'bsdiff_in_place': not args.extract_bsdiff}
        if args.bspatch_path:
          dargs['bspatch_path'] = args.bspatch_path
        if args.puffpatch_path:
          dargs['puffpatch_path'] = args.puffpatch_path
        if args.assert_type == _TYPE_DELTA:
          dargs['old_parts'] = dict(zip(args.part_names, args.src_part_paths))

        out_dst_parts = {}
        file_handles = []
        if args.out_dst_part_paths is not None:
          for name, path in zip(args.part_names, args.out_dst_part_paths):
            handle = open(path, 'wb+')
            file_handles.append(handle)
            out_dst_parts[name] = handle.name
        else:
          for name in args.part_names:
            handle = tempfile.NamedTemporaryFile()
            file_handles.append(handle)
            out_dst_parts[name] = handle.name

        payload.Apply(out_dst_parts, **dargs)

        # If destination kernel and rootfs partitions are not given, then this
        # just becomes an apply operation with no check.
        if CheckApplyPayload(args):
          # Prior to comparing, add the unused space past the filesystem
          # boundary in the new target partitions to become the same size as
          # the given partitions. This will truncate to larger size.
          for part_name, out_dst_part, dst_part in zip(args.part_names,
                                                       file_handles,
                                                       args.dst_part_paths):
            out_dst_part.truncate(os.path.getsize(dst_part))

            # Compare resulting partitions with the ones from the target image.
            if not filecmp.cmp(out_dst_part.name, dst_part):
              raise error.PayloadError(
                  'Resulting %s partition corrupted.' % part_name)

        # Close the output files. If args.out_dst_* was not given, then these
        # files are created as temp files and will be deleted upon close().
        for handle in file_handles:
          handle.close()
    except error.PayloadError as e:
      sys.stderr.write('Error: %s\n' % e)
      return 1

  return 0


if __name__ == '__main__':
  sys.exit(main(sys.argv))
