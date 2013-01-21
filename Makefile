SUPPORTED_PLATFORMS=linux-gnu darwin12 darwin11

ifeq (,$(findstring $(OSTYPE),$(SUPPORTED_PLATFORMS)))

all %:
	@echo The OS environment variable is set to [$(OSTYPE)].
	@echo Please set the OS environment variable to one of the following:
	@echo $(SUPPORTED_PLATFORMS)

else

all:

include makefile.$(OSTYPE)

endif
