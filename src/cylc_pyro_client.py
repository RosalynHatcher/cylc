#!/usr/bin/env python

#         __________________________
#         |____C_O_P_Y_R_I_G_H_T___|
#         |                        |
#         |  (c) NIWA, 2008-2010   |
#         | Contact: Hilary Oliver |
#         |  h.oliver@niwa.co.nz   |
#         |    +64-4-386 0461      |
#         |________________________|


import os, sys
import Pyro.core, Pyro.errors
from optparse import OptionParser
from time import sleep
from port_scan import get_port, check_port

class client:
    def __init__( self, suite, owner, host, port ):
        self.suite = suite
        self.owner = owner
        self.host = host
        self.port = port

    def get_proxy( self, target ):
        if self.port:
            port = self.port
            if not check_port( self.suite, self.owner, self.host, self.port ):
                msg = self.suite + "(" + self.owner + ") not found at " + self.host + ":" + port
                raise Pyro.errors.NamingError( msg )
        else:
            print "Scanning for " + self.suite + " ..."
            found, port = get_port( self.suite, self.owner, self.host )
            if not found:
                msg = self.suite + "(" + self.owner + ") not found on " + self.host 
                raise Pyro.errors.NamingError( msg )

        # get a pyro proxy for the target object
        objname = self.owner + '.' + self.suite + '.' + target
        # the following will also raise a NamingError if the target object is not found
        return Pyro.core.getProxyForURI('PYROLOC://' + self.host + ':' + str(port) + '/' + objname )
