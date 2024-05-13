ProperClipping = ProperClipping or {}

local cvar_clips = CreateConVar("proper_clipping_max_visual", "6", FCVAR_ARCHIVE, "Max clips a entity can have", 0, 6)

----------------------------------------

local function renderOverride(self)
	if not self or not self:IsValid() then return end
	if not self.Clipped or not self.ClipData then return end
	
	local prev = render.EnableClipping(true)
	local max = cvar_clips:GetInt()
	local planes = 0
	local inside = false
	
	local pos = self:GetPos()
	local ang = self:GetAngles()
	
	for i, clip in ipairs(self.ClipData) do
		if not inside and clip.inside then
			inside = true
		end
		
		if i <= max then
			planes = i
			
			local norm = Vector(clip.norm)
			norm:Rotate(ang)
			
			render.PushCustomClipPlane(norm, norm:Dot(pos + norm * clip.dist))
		end
	end
	
	self:DrawModel()
	
	if inside then
		render.CullMode(MATERIAL_CULLMODE_CW)
		self:DrawModel()
		render.CullMode(MATERIAL_CULLMODE_CCW)
	end
	
	for _ = 1, planes do
		render.PopCustomClipPlane()
	end
	
	render.EnableClipping(prev)
end

function ProperClipping.AddVisualClip(ent, norm, dist, inside, physics)
	if not ent.Clipped then
		ent.RenderOverride_preclipping = ent.RenderOverride
		ent.RenderOverride = renderOverride
		
		ent.Clipped = true
		ent.ClipData = {}
	end
	
	table.insert(ent.ClipData, {
		origin = norm * dist,
		norm = norm,
		n = norm:Angle(),
		dist = dist,
		d = norm:Dot(norm * dist - (ent.OBBCenterOrg or ent:OBBCenter())),
		inside = inside,
		physics = physics,
		new = true -- still no clue what this is for, meh w/e
	})
	
	hook.Run("ProperClippingClipAdded", ent, norm, dist, inside, physics)
end

function ProperClipping.RemoveVisualClips(ent)
	if not ent.Clipped then return end
	
	ent.Clipped = nil
	ent.ClipData = nil
	
	ent.RenderOverride = ent.RenderOverride_preclipping
	ent.RenderOverride_preclipping = nil
	
	hook.Run("ProperClippingClipsRemoved", ent)
end

----------------------------------------

local clip_queue = {}

local function attemptClip(id, clips)
	local ent = Entity(id)
	if not IsValid(ent) then return false end
	-- Wait for the spawneffect to end before we clip the entity
	if ent.SpawnEffect then return false end
	
	ProperClipping.RemoveVisualClips(ent)
	ProperClipping.ResetPhysics(ent)
	
	local norms, dists = {}, {}
	local physcount = 1
	for _, clip in ipairs(clips) do
		local norm, dist, inside, physics = unpack(clip)
		
		ProperClipping.AddVisualClip(ent, norm, dist, inside, physics)
		
		if physics then
			norms[physcount] = norm
			dists[physcount] = dist
			physcount = physcount + 1
		end
	end
	
	if physcount ~= 1 then
		ProperClipping.ClipPhysics(ent, norms, dists)
	end
	
	return true
end

timer.Create("proper_clipping_attemptclip", 0.1, 0, function()
	for id, clips in pairs(clip_queue) do
		if attemptClip(id, clips) then
			clip_queue[id] = nil
		end
	end
end)

net.Receive("proper_clipping", function()
	local id = net.ReadUInt(14)
	local add = net.ReadBool()
	
	if not add then
		clip_queue[id] = nil
		
		local ent = Entity(id)
		if not IsValid(ent) then return end
		
		ProperClipping.RemoveVisualClips(ent)
		ProperClipping.ResetPhysics(ent)
		
		return
	end
	
	local clips = {}
	
	for i = 1, net.ReadUInt(4) do
		clips[i] = {
			Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat()),
			net.ReadFloat(),
			net.ReadBool(),
			net.ReadBool()
		}
	end
	
	if not attemptClip(id, clips) then
		clip_queue[id] = clips
	end
end)
