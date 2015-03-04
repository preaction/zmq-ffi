package ZMQ::FFI::ZMQ2::Socket;

use strict;
use warnings;

use ZMQ::FFI::Common;
use FFI::Platypus;

use Moo;
use namespace::clean;

with qw(
    ZMQ::FFI::SocketRole
    ZMQ::FFI::ErrorHandler
);

my $FFI_LOADED;

sub BUILD {
    my ($self) = @_;

    unless ($FFI_LOADED) {
        _load_common_ffi($self->soname);
        _load_zmq2_ffi($self->soname);
        $FFI_LOADED = 1;
    }

}

sub send {
    # 0: self
    # 1: msg
    # 2: flags

    
}

sub disconnect {
    my ($self) = @_;

    $self->bad_version("disconnect not available in zmq 2.x");
}

sub unbind {
    my ($self) = @_;

    $self->bad_version("unbind not available in zmq 2.x");
}


sub _load_zmq2_ffi {
    my ($soname) = @_;

    $ffi = FFI::Platypus->new( lib => $soname );

    $ffi->attach(
        'zmq_send' => ['pointer', 'pointer', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_recv' => ['pointer', 'pointer', 'int'] => 'int'
    );
}

1;
