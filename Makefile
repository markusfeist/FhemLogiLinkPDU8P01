
/opt/fhem/FHEM/%.pm: FHEM/%.pm
	sudo cp $< $@

deploylocal: /opt/fhem/FHEM/51_LLPDU8P01.pm
	sudo /etc/init.d/fhem stop || true
	sudo systemctl stop fhem || true
	sudo rm /opt/fhem/log/fhem-*.log || true
	sudo cp test/fhem.cfg /opt/fhem/fhem.cfg
	sudo rm /opt/fhem/log/fhem.save || true
	cd /opt/fhem && sudo perl ./contrib/commandref_join.pl
	test -e /etc/init.d/fhem && sudo TZ=Europe/Berlin /etc/init.d/fhem start || true
	test -e /etc/init.d/fhem || sudo TZ=Europe/Berlin systemctl start fhem

undeploylocal:
	sudo /etc/init.d/fhem stop
	sudo systemctl stop fhem || true
	sudo rm /opt/fhem/FHEM/51_LLPDU8P01.pm
	cd /opt/fhem && sudo TZ=Europe/Berlin /usr/bin/perl fhem.pl fhem.cfg

test: deploylocal
	@echo === Starte Tests ===
	test/test.sh 01
	@echo === Alles Tests ok beendet ===
