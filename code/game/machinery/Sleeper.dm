/obj/machinery/sleeper
	name = "sleeper"
	desc = "A fancy bed with built-in injectors, a dialysis machine, and a limited health scanner."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeper_0"
	density = TRUE
	anchored = TRUE
	clicksound = 'sound/machines/buttonbeep.ogg'
	clickvol = 30
	base_type = /obj/machinery/sleeper
	construct_state = /decl/machine_construction/default/panel_closed
	uncreated_component_parts = null
	stat_immune = 0
	machine_name = "sleeper"
	machine_desc = "Sleepers are high-powered, full-body beds that can synthesize and inject simple chemicals, as well as dialyze substances from a patient's blood and slow down their body functions."
	var/mob/living/carbon/human/occupant = null
	var/list/base_chemicals = list("Inaprovaline" = /datum/reagent/inaprovaline, "Paracetamol" = /datum/reagent/paracetamol, "Dylovene" = /datum/reagent/dylovene, "Dexalin" = /datum/reagent/dexalin)
	var/list/available_chemicals = list()
	var/list/upgrade_chemicals = list("Kelotane" = /datum/reagent/kelotane)
	var/list/upgrade2_chemicals = list("Hyronalin" = /datum/reagent/hyronalin)
	var/list/antag_chemicals = list("Hair Remover" = /datum/reagent/toxin/hair_remover, "Chloral Hydrate" = /datum/reagent/chloralhydrate)
	var/obj/item/reagent_containers/glass/beaker = null
	var/filtering = 0
	var/pump
	var/list/stasis_settings = list(1, 2, 5, 10)
	var/stasis = 1
	var/synth_modifier = 1
	var/pump_speed
	var/stasis_power = 5 KILOWATTS

	idle_power_usage = 15
	active_power_usage = 1 KILOWATTS //builtin health analyzer, dialysis machine, injectors.

/obj/machinery/sleeper/Initialize(mapload, d = 0, populate_parts = TRUE)
	. = ..()
	if(populate_parts)
		beaker = new /obj/item/reagent_containers/glass/beaker/large(src)
	update_icon()

/obj/machinery/sleeper/examine(mob/user, distance)
	. = ..()
	if (distance <= 1)
		if (beaker)
			to_chat(user, "It is loaded with a beaker.")
		if(occupant)
			occupant.examine(arglist(args))
		if (emagged && user.skill_check(SKILL_MEDICAL, SKILL_EXPERT))
			to_chat(user, "The sleeper chemical synthesis controls look tampered with.")


/obj/machinery/sleeper/Process()
	if(inoperable())
		return

	if(filtering > 0)
		if(beaker)
			if(beaker.reagents.total_volume < beaker.reagents.maximum_volume)
				var/pumped = 0
				for(var/datum/reagent/x in occupant.reagents.reagent_list)
					occupant.reagents.trans_to_obj(beaker, pump_speed)
					pumped++
				if(ishuman(occupant))
					occupant.vessel.trans_to_obj(beaker, pumped + 1)
		else
			toggle_filter()
	if(pump > 0)
		if(beaker && istype(occupant))
			if(beaker.reagents.total_volume < beaker.reagents.maximum_volume)
				var/datum/reagents/ingested = occupant.get_ingested_reagents()
				if(ingested)
					for(var/datum/reagent/x in ingested.reagent_list)
						ingested.trans_to_obj(beaker, pump_speed)
		else
			toggle_pump()

	if(iscarbon(occupant) && stasis > 1)
		occupant.SetStasis(stasis)
		if (occupant.stat == UNCONSCIOUS && prob(2))
			to_chat(occupant, SPAN_NOTICE(SPAN_BOLD("... [pick("comfy", "feels slow", "warm")] ...")))

/obj/machinery/sleeper/on_update_icon()
	if(!occupant)
		icon_state = "sleeper_0"
	else if(inoperable())
		icon_state = "sleeper_1"
	else
		icon_state = "sleeper_2"

/obj/machinery/sleeper/DefaultTopicState()
	return GLOB.outside_state

/obj/machinery/sleeper/interface_interact(mob/user)
	ui_interact(user)
	return TRUE

/obj/machinery/sleeper/ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = 1, datum/topic_state/state = GLOB.outside_state)
	var/data[0]

	data["power"] = inoperable() ? 0 : 1

	var/list/reagents = list()
	for(var/T in available_chemicals)
		var/list/reagent = list()
		reagent["name"] = T
		if(occupant && occupant.reagents)
			reagent["amount"] = occupant.reagents.get_reagent_amount(available_chemicals[T])
		reagents += list(reagent)
	data["reagents"] = reagents.Copy()

	if(istype(occupant))
		var/scan = user.skill_check(SKILL_MEDICAL, SKILL_ADEPT) ? medical_scan_results(occupant) : "<span class='white'><b>Contains: \the [occupant]</b></span>"
		scan = replacetext(scan,"'scan_notice'","'white'")
		scan = replacetext(scan,"'scan_warning'","'average'")
		scan = replacetext(scan,"'scan_danger'","'bad'")
		data["occupant"] =scan
	else
		data["occupant"] = 0
	if(beaker)
		data["beaker"] = beaker.reagents.get_free_space()
	else
		data["beaker"] = -1
	data["filtering"] = filtering
	data["pump"] = pump
	data["stasis"] = stasis
	data["skill_check"] = user.skill_check(SKILL_MEDICAL, SKILL_BASIC)

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "sleeper.tmpl", "Sleeper UI", 600, 600, state = state)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)

/obj/machinery/sleeper/CanUseTopic(user)
	if(user == occupant)
		to_chat(usr, "<span class='warning'>You can't reach the controls from the inside.</span>")
		return STATUS_CLOSE
	. = ..()

/obj/machinery/sleeper/OnTopic(user, href_list)
	if(href_list["eject"])
		go_out()
		return TOPIC_REFRESH
	if(href_list["beaker"])
		remove_beaker()
		return TOPIC_REFRESH
	if(href_list["filter"])
		if(filtering != text2num(href_list["filter"]))
			toggle_filter()
			return TOPIC_REFRESH
	if(href_list["pump"])
		if(filtering != text2num(href_list["pump"]))
			toggle_pump()
			return TOPIC_REFRESH
	if(href_list["chemical"] && href_list["amount"])
		if(occupant && occupant.stat != DEAD)
			if(href_list["chemical"] in available_chemicals) // Your hacks are bad and you should feel bad
				inject_chemical(user, href_list["chemical"], text2num(href_list["amount"]))
				return TOPIC_REFRESH
	if(href_list["stasis"])
		var/nstasis = text2num(href_list["stasis"])
		if(stasis != nstasis && (nstasis in stasis_settings))
			stasis = text2num(href_list["stasis"])
			change_power_consumption(initial(active_power_usage) + stasis_power * (stasis-1), POWER_USE_ACTIVE)
			return TOPIC_REFRESH

/obj/machinery/sleeper/state_transition(decl/machine_construction/default/new_state)
	. = ..()
	if(istype(new_state))
		updateUsrDialog()
		go_out()

/obj/machinery/sleeper/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/reagent_containers/glass))
		add_fingerprint(user)
		if(!beaker)
			if(!user.unEquip(I, src))
				return
			beaker = I
			user.visible_message("<span class='notice'>\The [user] adds \a [I] to \the [src].</span>", "<span class='notice'>You add \a [I] to \the [src].</span>")
		else
			to_chat(user, "<span class='warning'>\The [src] has a beaker already.</span>")
		return TRUE
	return ..()

/obj/machinery/sleeper/MouseDrop_T(mob/target, mob/user)
	if(!CanMouseDrop(target, user))
		return
	if(!istype(target))
		return
	if(target.buckled)
		to_chat(user, "<span class='warning'>Unbuckle the subject before attempting to move them.</span>")
		return
	if(panel_open)
		to_chat(user, "<span class='warning'>Close the maintenance panel before attempting to place the subject in the sleeper.</span>")
		return
	go_in(target, user)

/obj/machinery/sleeper/relaymove(mob/user)
	..()
	go_out()

/obj/machinery/sleeper/emp_act(severity)
	if(filtering)
		toggle_filter()

	if(inoperable())
		..(severity)
		return

	go_out()

	..(severity)
/obj/machinery/sleeper/proc/toggle_filter()
	if(!occupant || !beaker)
		filtering = 0
		return
	to_chat(occupant, "<span class='warning'>You feel like your blood is being sucked away.</span>")
	filtering = !filtering

/obj/machinery/sleeper/proc/toggle_pump()
	if(!occupant || !beaker)
		pump = 0
		return
	to_chat(occupant, "<span class='warning'>You feel a tube jammed down your throat.</span>")
	pump = !pump

/obj/machinery/sleeper/proc/go_in(mob/M, mob/user)
	if(!M)
		return
	if(inoperable())
		return
	if(occupant)
		to_chat(user, "<span class='warning'>\The [src] is already occupied.</span>")
		return

	if(M == user)
		visible_message("\The [user] starts climbing into \the [src].")
	else
		visible_message("\The [user] starts putting [M] into \the [src].")

	if(do_after(user, 2 SECONDS, src, DO_PUBLIC_UNIQUE))
		if(occupant)
			to_chat(user, "<span class='warning'>\The [src] is already occupied.</span>")
			return
		set_occupant(M)

/obj/machinery/sleeper/proc/go_out()
	if(!occupant)
		return
	if(occupant.client)
		occupant.client.eye = occupant.client.mob
		occupant.client.perspective = MOB_PERSPECTIVE
	occupant.dropInto(loc)
	set_occupant(null)

	for(var/obj/O in (contents - component_parts)) // In case an object was dropped inside or something. Excludes the beaker and component parts.
		if(O == beaker)
			continue
		O.dropInto(loc)
	toggle_filter()

/obj/machinery/sleeper/AltClick(mob/user)
	if(CanDefaultInteract(user))
		go_out()
	else
		..()

/obj/machinery/sleeper/proc/set_occupant(mob/living/carbon/occupant)
	src.occupant = occupant
	update_icon()
	if(!occupant)
		SetName(initial(name))
		update_use_power(POWER_USE_IDLE)
		return
	occupant.forceMove(src)
	occupant.stop_pulling()
	if(occupant.client)
		occupant.client.perspective = EYE_PERSPECTIVE
		occupant.client.eye = src
	SetName("[name] ([occupant])")
	update_use_power(POWER_USE_ACTIVE)

/obj/machinery/sleeper/proc/remove_beaker()
	if(beaker)
		beaker.dropInto(loc)
		beaker = null
		toggle_filter()
		toggle_pump()

/obj/machinery/sleeper/proc/inject_chemical(mob/living/user, chemical_name, amount)
	if(inoperable())
		return

	var/chemical_type = available_chemicals[chemical_name]
	if(occupant && occupant.reagents)
		if(occupant.reagents.get_reagent_amount(chemical_type) + amount <= 20)
			use_power_oneoff(amount * CHEM_SYNTH_ENERGY * synth_modifier)
			occupant.reagents.add_reagent(chemical_type, amount)
			var/datum/reagent/R = chemical_type
			if (initial(R.should_admin_log))
				admin_inject_log(user, occupant, src, chemical_type, amount)
			to_chat(user, "Occupant now has [occupant.reagents.get_reagent_amount(chemical_type)] unit\s of [chemical_name] in their bloodstream.")
		else
			to_chat(user, "The subject has too many chemicals.")
	else
		to_chat(user, "There's no suitable occupant in \the [src].")

/obj/machinery/sleeper/RefreshParts()
	..()
	var/T = clamp(total_component_rating_of_type(/obj/item/stock_parts/scanning_module), 1, 10)
	T = max(T,1)
	synth_modifier = 1/T
	pump_speed = 2 + T

	T = total_component_rating_of_type(/obj/item/stock_parts/manipulator)
	available_chemicals = base_chemicals.Copy()
	if (T >= 4)
		available_chemicals |= upgrade_chemicals
	if (T >= 6)
		available_chemicals |= upgrade2_chemicals


/obj/machinery/sleeper/emag_act(remaining_charges, mob/user)
	emagged = !emagged
	to_chat(user, "<span class='danger'>You [emagged ? "disable" : "enable"] \the [src]'s chemical synthesis safety checks.</span>")

	if (emagged)
		available_chemicals |= antag_chemicals
	else
		available_chemicals -= antag_chemicals
	return 1
