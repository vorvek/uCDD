# SPDX-FileCopyrightText: 2026 vorvek
# SPDX-License-Identifier: GPL-3.0-only

"""Make disposable FAT16 test disks from an external FreeDOS image."""

import struct


class Fat16:
    def empty_larger(self, size_mib=128):
        image = bytearray(size_mib*1024*1024)
        image[:self.start+512] = self.image[:self.start+512]
        sectors = (len(image)-self.start)//512
        spc = self.spc
        while sectors//spc > 65524:
            spc *= 2
        image[self.start+13] = spc
        fat_sectors = 1
        while True:
            clusters = (sectors-1-self.entries*32//512-self.nfats*fat_sectors)//spc
            required = ((clusters+2)*2+511)//512
            if required <= fat_sectors:
                break
            fat_sectors = required
        if not 4085 <= clusters <= 65524:
            raise ValueError('The disk size is outside the FAT16 range.')
        struct.pack_into('<I', image, 458, sectors)
        image[450] = 0x0e if sectors >= 1024*16*63 else 6
        last = len(image)//512-1
        cylinder, remainder = divmod(last, 16*63)
        head, sector = divmod(remainder, 63)
        image[451:454] = (bytes((254, 255, 255)) if cylinder > 1023 else
                            bytes((head, sector+1 | (cylinder >> 2 & 0xc0), cylinder & 0xff)))
        struct.pack_into('<H', image, self.start+19, 0)
        struct.pack_into('<I', image, self.start+32, sectors)
        struct.pack_into('<H', image, self.start+22, fat_sectors)
        disk = Fat16(image)
        for copy in range(disk.nfats):
            offset = disk.fat+copy*fat_sectors*512
            disk.image[offset:offset+4] = bytes([0xf8, 0xff, 0xff, 0xff])
        return disk

    def __init__(self, image):
        self.image = bytearray(image)
        self.start = struct.unpack_from('<I', image, 454)[0] * 512
        bpb = self.start
        self.bps = struct.unpack_from('<H', image, bpb + 11)[0]
        self.spc = image[bpb + 13]
        reserved = struct.unpack_from('<H', image, bpb + 14)[0]
        self.nfats = image[bpb + 16]
        self.entries = struct.unpack_from('<H', image, bpb + 17)[0]
        self.fat_sectors = struct.unpack_from('<H', image, bpb + 22)[0]
        if self.bps != 512 or not self.entries or not self.fat_sectors:
            raise ValueError('A FAT16 disk image is required.')
        self.fat = bpb + reserved * self.bps
        self.root = self.fat + self.nfats * self.fat_sectors * self.bps
        self.data = self.root + ((self.entries * 32 + 511) // 512) * 512
        self.cluster_bytes = self.spc * self.bps
        self.next_cluster = 2

    def chain(self, cluster):
        seen = set()
        while 2 <= cluster < 0xfff8:
            if cluster in seen:
                raise ValueError('The FAT chain contains a loop.')
            seen.add(cluster)
            offset = self.data + (cluster - 2) * self.cluster_bytes
            yield self.image[offset:offset + self.cluster_bytes]
            cluster = struct.unpack_from('<H', self.image, self.fat + cluster * 2)[0]

    def directory(self, cluster=0):
        data = (self.image[self.root:self.root + self.entries * 32]
                if not cluster else b''.join(self.chain(cluster)))
        result = {}
        for offset in range(0, len(data), 32):
            item = data[offset:offset + 32]
            if item[0] == 0:
                break
            if item[0] == 0xe5 or item[11] & 8:
                continue
            name = item[:8].decode('ascii').rstrip()
            ext = item[8:11].decode('ascii').rstrip()
            if ext:
                name += '.' + ext
            result[name] = (struct.unpack_from('<H', item, 26)[0],
                            struct.unpack_from('<I', item, 28)[0], item[11])
        return result

    def read(self, path):
        cluster = 0
        for part in path.upper().replace('\\', '/').split('/'):
            cluster, size, _ = self.directory(cluster)[part]
        return bytes(b''.join(self.chain(cluster))[:size])

    def clear(self):
        for index in range(self.nfats):
            offset = self.fat + index * self.fat_sectors * self.bps
            size = self.fat_sectors * self.bps
            self.image[offset + 4:offset + size] = bytes(size - 4)
        self.image[self.root:] = bytes(len(self.image) - self.root)
        self.next_cluster = 2

    def add(self, name, content, attributes=0x20):
        base, _, ext = name.upper().partition('.')
        if not 1 <= len(base) <= 8 or len(ext) > 3:
            raise ValueError('The file name must use the DOS 8.3 format.')
        encoded = (base.ljust(8) + ext.ljust(3)).encode('ascii')
        count = (len(content) + self.cluster_bytes - 1) // self.cluster_bytes
        first = self.next_cluster if count else 0
        if self.data + (self.next_cluster - 2 + count) * self.cluster_bytes > len(self.image):
            raise ValueError('The test disk is full.')
        for index in range(count):
            cluster = self.next_cluster
            self.next_cluster += 1
            following = 0xffff if index + 1 == count else cluster + 1
            for copy in range(self.nfats):
                offset = self.fat + copy * self.fat_sectors * 512 + cluster * 2
                struct.pack_into('<H', self.image, offset, following)
            offset = self.data + (cluster - 2) * self.cluster_bytes
            part = content[index * self.cluster_bytes:(index + 1) * self.cluster_bytes]
            self.image[offset:offset + len(part)] = part
        for offset in range(self.root, self.root + self.entries * 32, 32):
            if self.image[offset] == 0:
                item = bytearray(32)
                item[:11] = encoded
                item[11] = attributes
                struct.pack_into('<H', item, 26, first)
                struct.pack_into('<I', item, 28, len(content))
                self.image[offset:offset + 32] = item
                return
        raise ValueError('The root directory is full.')

    def add_directory(self, name, files):
        if len(files) > self.cluster_bytes//32 - 2:
            raise ValueError('The test directory is too large.')
        cluster = self.next_cluster
        data = bytearray(self.cluster_bytes)
        data[:11], data[32:43] = b'.          ', b'..         '
        data[11] = data[43] = 0x10
        struct.pack_into('<H', data, 26, cluster)
        root_entry = next(offset for offset in range(self.root, self.root + self.entries*32, 32)
                          if self.image[offset] == 0)
        self.add(name, data, 0x10)
        struct.pack_into('<I', self.image, root_entry+28, 0)
        directory = self.data + (cluster - 2)*self.cluster_bytes
        for index, (filename, content) in enumerate(files.items(), 2):
            entry = next(offset for offset in range(self.root, self.root + self.entries*32, 32)
                         if self.image[offset] == 0)
            self.add(filename, content)
            self.image[directory+index*32:directory+(index+1)*32] = self.image[entry:entry+32]
            self.image[entry:entry+32] = bytes(32)
